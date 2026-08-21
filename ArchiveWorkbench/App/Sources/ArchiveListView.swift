import AppKit
import UniformTypeIdentifiers
import ArchiveDomain
import SwiftUI

// MARK: - Drag Helpers

/// Sendable payload stored in a drag promise's userInfo so the nonisolated
/// promise-delegate callbacks can identify the entry without main-actor state.
private struct EntryDragInfo: Sendable {
    let id: ArchiveEntryID?
    let name: String
    let isDirectory: Bool
    let fullPath: String
}

/// Wraps the non-Sendable promise completion handler so it can be captured by
/// a @Sendable task closure and invoked from any thread exactly once.
private final class PromiseCompletion: @unchecked Sendable {
    private let handler: (Error?) -> Void
    init(_ handler: @escaping (Error?) -> Void) { self.handler = handler }
    func call(_ error: Error?) { handler(error) }
}

// MARK: - Tree Node

/// A node in the file-system tree displayed by the outline view.
/// Directory nodes may be synthetic (inferred from path components) or backed
/// by an explicit directory entry in the archive.
final class FileTreeNode: Hashable {
    let name: String
    let fullPath: String
    let isDirectory: Bool
    let entry: ArchiveEntry?
    var children: [FileTreeNode] = []
    var pendingBadge: String?
    var isPendingRemoved = false

    init(name: String, fullPath: String, isDirectory: Bool, entry: ArchiveEntry? = nil) {
        self.name = name
        self.fullPath = fullPath
        self.isDirectory = isDirectory
        self.entry = entry
    }

    static func == (lhs: FileTreeNode, rhs: FileTreeNode) -> Bool {
        lhs.fullPath == rhs.fullPath
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fullPath)
    }
}

// MARK: - Tree Builder

enum FileTreeBuilder {
    /// Builds a tree from flat archive entries using a trie-like approach.
    /// Entries whose path ends with "/" are treated as explicit directory entries.
    /// Intermediate path components become synthetic folder nodes.
    ///
    /// When `flat` is true (search results), each entry becomes a single
    /// root-level leaf node with no hierarchy, so matches nested inside folders
    /// are shown as real rows rather than hidden under a collapsed parent.
    static func build(from entries: [ArchiveEntry], flat: Bool = false) -> [FileTreeNode] {
        if flat {
            return entries.compactMap { entry in
                let path = entry.displayPath
                let isDirectory = path.hasSuffix("/")
                let cleanPath = isDirectory ? String(path.dropLast()) : path
                guard !cleanPath.split(separator: "/").isEmpty else { return nil }
                let name = cleanPath.split(separator: "/").last.map(String.init) ?? cleanPath
                return FileTreeNode(name: name, fullPath: cleanPath, isDirectory: isDirectory, entry: entry)
            }
        }

        final class TrieNode {
            var children: [String: TrieNode] = [:]
            var entry: ArchiveEntry?
            var isExplicitDirectory = false
        }

        let root = TrieNode()

        for entry in entries {
            let path = entry.displayPath
            let isExplicitDirectory = path.hasSuffix("/")
            let cleanPath = isExplicitDirectory ? String(path.dropLast()) : path
            let components = cleanPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !components.isEmpty else { continue }

            var current = root
            for component in components {
                if let child = current.children[component] {
                    current = child
                } else {
                    let child = TrieNode()
                    current.children[component] = child
                    current = child
                }
            }
            current.entry = entry
            if isExplicitDirectory {
                current.isExplicitDirectory = true
            }
        }

        func materialize(trie: TrieNode, name: String, pathPrefix: String) -> FileTreeNode {
            let fullPath = pathPrefix.isEmpty ? name : pathPrefix + "/" + name
            let isDirectory = !trie.children.isEmpty || trie.isExplicitDirectory
            let node = FileTreeNode(
                name: name,
                fullPath: fullPath,
                isDirectory: isDirectory,
                entry: trie.entry
            )
            node.children = trie.children.map { childName, childTrie in
                materialize(trie: childTrie, name: childName, pathPrefix: fullPath)
            }
            return node
        }

        return root.children.map { name, trie in
            materialize(trie: trie, name: name, pathPrefix: "")
        }
    }
}

// MARK: - Sort Support

enum TreeSortColumn: String {
    case name, size, date, type
}

struct TreeSortState {
    var column: TreeSortColumn = .name
    var ascending = true
}

// MARK: - Archive List View (Outline)

struct ArchiveListView: NSViewRepresentable {
    static let promisedFileContentType = "com.apple.pasteboard.promised-file-content-type"

    let entries: [ArchiveEntry]
    /// Identity of the currently open archive. Used to reset persisted view state
    /// (e.g. expansion) when the user switches to a different archive.
    let archiveSourceURL: URL?
    /// When true, entries are search results rendered as flat rows (no hierarchy).
    let isSearching: Bool
    let metadataByEntryID: [ArchiveEntryID: ArchiveEntryMetadata]
    @Binding var selection: ArchiveEntryID?
    var nestedArchiveEntryIDs: Set<ArchiveEntryID> = []
    var pendingChanges: [PendingChange] = []
    var canEdit: Bool = false
    var canExtractSelected: Bool = true
    var canExtract: Bool = true
    var isExtracting: Bool = false
    var onDelete: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onOpenNestedArchive: ((ArchiveEntryID) -> Void)? = nil
    var onOpenFile: ((ArchiveEntryID) -> Void)? = nil
    var onExtractSelected: (() -> Void)? = nil
    var onExtractFolder: ((String) -> Void)? = nil
    var onFolderSelectionChange: ((String?) -> Void)? = nil
    var onCopyPath: ((String) -> Void)? = nil
    var onAddFiles: ((_ urls: [URL], _ destinationFolder: String?) -> Void)? = nil
    var onMoveEntry: ((_ sourcePath: String, _ destinationPath: String) -> Void)? = nil
    var onMaterializeEntry: ((_ entryID: ArchiveEntryID, _ completion: @escaping @Sendable (Result<(file: URL, stagingRoot: URL), Error>) -> Void) -> Void)? = nil
    /// Whether a dropped URL is a supported archive; drives "drop archive to open".
    var onIsSupportedArchive: ((URL) -> Bool)? = nil
    /// Materializes an entire folder subtree for drag-out (folder path → stagingDir → folder URL).
    var onMaterializeFolder: ((_ folderPath: String, _ stagingDir: URL) async throws -> URL)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let localization = AppLocalization()
        let outline = DeleteCapturingOutlineView()
        outline.deleteAction = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onDelete?()
        }
        outline.renameAction = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onRename?()
        }
        outline.canEdit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.canEdit ?? false
        }
        outline.openNestedAction = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return }
            guard let entryID = coordinator.parent.selection else { return }
            coordinator.parent.onOpenNestedArchive?(entryID)
        }
        outline.canOpenNested = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return false }
            guard let entryID = coordinator.parent.selection else { return false }
            return coordinator.parent.nestedArchiveEntryIDs.contains(entryID)
        }
        outline.identifier = NSUserInterfaceItemIdentifier("归档文件列表")
        outline.setAccessibilityIdentifier("归档文件列表")
        outline.usesAlternatingRowBackgroundColors = false
        outline.allowsMultipleSelection = false
        outline.delegate = context.coordinator
        outline.dataSource = context.coordinator
        outline.indentationPerLevel = 16
        outline.rowHeight = 24
        // Transparent list background so the empty area below the last row blends
        // with the window (no striped/zebra artifact in dark mode); selection
        // highlight is driven independently by selectionHighlightStyle.
        outline.backgroundColor = .clear

        outline.selectionHighlightStyle = .regular
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.outlineViewDoubleClicked(_:))

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = localization.string("名称")
        nameColumn.width = 300
        nameColumn.minWidth = 100
        nameColumn.resizingMask = .autoresizingMask
        outline.addTableColumn(nameColumn)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = localization.string("大小")
        sizeColumn.width = 72
        sizeColumn.minWidth = 56
        outline.addTableColumn(sizeColumn)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = localization.string("修改日期")
        dateColumn.width = 118
        dateColumn.minWidth = 100
        outline.addTableColumn(dateColumn)

        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.title = localization.string("类型")
        typeColumn.width = 76
        typeColumn.minWidth = 56
        outline.addTableColumn(typeColumn)

        outline.outlineTableColumn = nameColumn

        // Enable sorting on all columns
        for column in outline.tableColumns {
            let sortDescriptor = NSSortDescriptor(key: column.identifier.rawValue, ascending: true)
            column.sortDescriptorPrototype = sortDescriptor
        }

        let menu = NSMenu()
        menu.delegate = context.coordinator
        let proSuffix = LicenseManager.shared.isProLicensed ? "" : " · Pro"
        let openItem = NSMenuItem(title: localization.string("打开"), action: #selector(Coordinator.contextOpen(_:)), keyEquivalent: "")
        openItem.target = context.coordinator
        menu.addItem(openItem)
        let extractItem = NSMenuItem(title: localization.string("解压选中") + proSuffix, action: #selector(Coordinator.contextExtract(_:)), keyEquivalent: "")
        extractItem.target = context.coordinator
        menu.addItem(extractItem)
        menu.addItem(.separator())
        let renameItem = NSMenuItem(title: localization.string("重命名…") + proSuffix, action: #selector(Coordinator.contextRename(_:)), keyEquivalent: "")
        renameItem.target = context.coordinator
        menu.addItem(renameItem)
        let deleteItem = NSMenuItem(title: localization.string("移除") + proSuffix, action: #selector(Coordinator.contextDelete(_:)), keyEquivalent: "")
        deleteItem.target = context.coordinator
        menu.addItem(deleteItem)
        menu.addItem(.separator())
        let copyPathItem = NSMenuItem(title: localization.string("拷贝路径"), action: #selector(Coordinator.contextCopyPath(_:)), keyEquivalent: "")
        copyPathItem.target = context.coordinator
        menu.addItem(copyPathItem)
        outline.menu = menu
        context.coordinator.outlineView = outline

        // Drag & drop: accept file URLs (drag-in from Finder) and our own
        // promised-file drags (internal move between folders).
        outline.registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType(Self.promisedFileContentType),
        ])
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.setDraggingSourceOperationMask(.move, forLocal: true)

        let scrollView = NSScrollView()
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let outline = scrollView.documentView as? NSOutlineView else { return }

        // When the user switches to a different archive, discard the previous
        // archive's expansion state so same-named folders are not pre-expanded.
        if context.coordinator.lastArchiveSourceURL != archiveSourceURL {
            context.coordinator.lastArchiveSourceURL = archiveSourceURL
            context.coordinator.expandedPaths = []
            context.coordinator.preSearchExpandedPaths = nil
            context.coordinator.didAutoExpandRoot = false
            // FileTreeNode equality is fullPath-based, so NSOutlineView would keep
            // same-named folders expanded across reloadData via its own internal
            // state. Collapse everything so no stale expansion survives the switch.
            outline.collapseItem(nil, collapseChildren: true)
        }

        let entriesChanged = context.coordinator.lastEntries != entries
            || context.coordinator.lastIsSearching != isSearching
        let pendingChanged = context.coordinator.lastPendingChanges != pendingChanges
        let treeRebuilt = entriesChanged || pendingChanged

        if treeRebuilt {
            let wasSearching = context.coordinator.lastIsSearching

            // Leaving search: the flat reload that ran on the way in already wiped
            // expandedPaths (via collapse callbacks), so restore the hierarchical
            // expansion snapshot taken when search began.
            if wasSearching && !isSearching, let snapshot = context.coordinator.preSearchExpandedPaths {
                context.coordinator.expandedPaths = snapshot
                context.coordinator.preSearchExpandedPaths = nil
            }

            context.coordinator.lastEntries = entries
            context.coordinator.lastIsSearching = isSearching
            context.coordinator.lastPendingChanges = pendingChanges

            // Capture expanded paths before reload
            let oldExpandedPaths = context.coordinator.expandedPaths

            // Entering search: snapshot the hierarchical expansion so it can be
            // restored when the search is cleared.
            if !wasSearching && isSearching {
                context.coordinator.preSearchExpandedPaths = oldExpandedPaths
            }

            context.coordinator.rebuildTree()
            outline.reloadData()

            // Reapply sort indicators
            let descriptor = NSSortDescriptor(key: context.coordinator.sortState.column.rawValue, ascending: context.coordinator.sortState.ascending)
            outline.sortDescriptors = [descriptor]

            // Restore expansion state, shallowest first so ancestors are expanded
            // before descendants (expanding a node under a collapsed parent is
            // dropped by NSOutlineView, which would lose nested expansion).
            let pathsByDepth = oldExpandedPaths.sorted {
                $0.components(separatedBy: "/").count < $1.components(separatedBy: "/").count
            }
            for path in pathsByDepth {
                if let item = context.coordinator.nodeByPath[path] {
                    outline.expandItem(item)
                }
            }
            // First reveal: a fresh archive with no prior expansion state shows a
            // single collapsed root that contradicts the "N items" header — a new
            // user reads that as "empty / broken" (iron rule #3). Expand the top
            // level once per archive open so the contents are immediately visible.
            if !isSearching, !context.coordinator.didAutoExpandRoot, oldExpandedPaths.isEmpty {
                context.coordinator.didAutoExpandRoot = true
                for node in context.coordinator.rootNodes where node.isDirectory {
                    outline.expandItem(node)
                    context.coordinator.expandedPaths.insert(node.fullPath)
                }
            }
        }

        // Restore selection (always, since selection may change independently)
        if let selected = selection {
            if let node = context.coordinator.nodeByEntryID[selected] {
                var row = outline.row(forItem: node)
                let selectionChanged = context.coordinator.lastRestoredSelectionID != selected
                if row < 0, selectionChanged || treeRebuilt {
                    // The selected entry is hidden under a collapsed parent (e.g.
                    // the auto-selected first file of a nested-only archive, or a
                    // search result whose folder collapsed on returning to the
                    // hierarchy). Expand its ancestors so the selected row is
                    // actually visible and the inspector/status bar match the list.
                    context.coordinator.expandAncestors(of: node, in: outline)
                    row = outline.row(forItem: node)
                }
                if row >= 0 && outline.selectedRow != row {
                    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outline.scrollRowToVisible(row)
                }
                context.coordinator.lastRestoredSelectionID = selected
            }
        } else {
            context.coordinator.lastRestoredSelectionID = nil
            if outline.selectedRow >= 0, context.coordinator.selectedNode?.isDirectory != true {
                outline.deselectAll(nil)
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSFilePromiseProviderDelegate {
        var parent: ArchiveListView
        var rootNodes: [FileTreeNode] = []
        var nodeByPath: [String: FileTreeNode] = [:]
        var nodeByEntryID: [ArchiveEntryID: FileTreeNode] = [:]
        var expandedPaths: Set<String> = []
        var didAutoExpandRoot = false
        var preSearchExpandedPaths: Set<String>?
        var sortState = TreeSortState()
        var lastEntries: [ArchiveEntry] = []
        var lastIsSearching = false
        var lastArchiveSourceURL: URL?
        var lastRestoredSelectionID: ArchiveEntryID?
        var lastPendingChanges: [PendingChange]?
        var selectedNode: FileTreeNode?
        var draggedNodes: [FileTreeNode] = []
        weak var outlineView: NSOutlineView?

        init(parent: ArchiveListView) {
            self.parent = parent
            super.init()
            rebuildTree()
        }

        func rebuildTree() {
            rootNodes = FileTreeBuilder.build(from: parent.entries, flat: parent.isSearching)
            insertPendingAdditions()
            sortNodes(&rootNodes)

            nodeByPath = [:]
            nodeByEntryID = [:]
            indexNodes(rootNodes)
            applyPendingMarkers()
        }

        /// Expands each directory ancestor of `node` (derived from its
        /// slash-separated `fullPath`) so a selected-but-hidden entry becomes a
        /// visible row. Expansion goes through the outline so the delegate keeps
        /// `expandedPaths` in sync across reloads.
        func expandAncestors(of node: FileTreeNode, in outline: NSOutlineView) {
            let components = node.fullPath.split(separator: "/").map(String.init)
            guard components.count > 1 else { return }
            var prefix = ""
            for component in components.dropLast() {
                prefix = prefix.isEmpty ? component : prefix + "/" + component
                if let ancestor = nodeByPath[prefix], ancestor.isDirectory {
                    outline.expandItem(ancestor)
                }
            }
        }

        private func insertPendingAdditions() {
            for change in parent.pendingChanges {
                guard case let .add(_, destinationPath) = change else { continue }
                insertPendingAddNode(at: destinationPath)
            }
        }

        private func insertPendingAddNode(at destinationPath: String) {
            let localization = AppLocalization()
            let components = destinationPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !components.isEmpty else { return }
            var parentNode: FileTreeNode?
            var prefix = ""
            for (index, component) in components.enumerated() {
                let fullPath = prefix.isEmpty ? component : prefix + "/" + component
                let isLast = index == components.count - 1
                let siblings = parentNode?.children ?? rootNodes
                if let existing = siblings.first(where: { $0.name == component }) {
                    if isLast { existing.pendingBadge = localization.string("待添加") }
                    parentNode = existing
                } else {
                    let node = FileTreeNode(name: component, fullPath: fullPath, isDirectory: !isLast)
                    if isLast { node.pendingBadge = localization.string("待添加") }
                    if let parent = parentNode {
                        parent.children.append(node)
                    } else {
                        rootNodes.append(node)
                    }
                    parentNode = node
                }
                prefix = fullPath
            }
        }

        private func applyPendingMarkers() {
            let localization = AppLocalization()
            for change in parent.pendingChanges {
                switch change {
                case let .remove(entryPath):
                    if let node = nodeByPath[entryPath] {
                        markRemoved(node)
                    }
                case let .rename(from, to):
                    guard let node = nodeByPath[from] else { continue }
                    node.pendingBadge = "→ " + (to as NSString).lastPathComponent
                case let .replace(entryPath, _):
                    nodeByPath[entryPath]?.pendingBadge = localization.string("待替换")
                case .add:
                    break
                }
            }
        }

        private func markRemoved(_ node: FileTreeNode) {
            node.isPendingRemoved = true
            for child in node.children {
                markRemoved(child)
            }
        }

        private func indexNodes(_ nodes: [FileTreeNode]) {
            for node in nodes {
                nodeByPath[node.fullPath] = node
                if let entry = node.entry {
                    nodeByEntryID[entry.id] = node
                }
                if !node.children.isEmpty {
                    indexNodes(node.children)
                }
            }
        }

        func sortNodes(_ nodes: inout [FileTreeNode]) {
            nodes.sort { lhs, rhs in
                // Directories always come first regardless of sort direction
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                let result: ComparisonResult
                switch sortState.column {
                case .name:
                    result = lhs.name.localizedStandardCompare(rhs.name)
                case .size:
                    let lhsSize = sizeSortValue(for: lhs)
                    let rhsSize = sizeSortValue(for: rhs)
                    if lhsSize == rhsSize {
                        result = lhs.name.localizedStandardCompare(rhs.name)
                    } else {
                        result = lhsSize < rhsSize ? .orderedAscending : .orderedDescending
                    }
                case .date:
                    let lhsDate = dateSortValue(for: lhs)
                    let rhsDate = dateSortValue(for: rhs)
                    if lhsDate == rhsDate {
                        result = lhs.name.localizedStandardCompare(rhs.name)
                    } else {
                        result = lhsDate < rhsDate ? .orderedAscending : .orderedDescending
                    }
                case .type:
                    let lhsType = typeValue(for: lhs)
                    let rhsType = typeValue(for: rhs)
                    result = lhsType.localizedStandardCompare(rhsType)
                }
                return sortState.ascending ? result == .orderedAscending : result == .orderedDescending
            }
            // Recursively sort children
            for node in nodes where !node.children.isEmpty {
                sortNodes(&node.children)
            }
        }

        private func sizeSortValue(for node: FileTreeNode) -> Double {
            guard let entry = node.entry,
                  let metadata = parent.metadataByEntryID[entry.id] else { return 0 }
            return Double(metadata.sizeBytes)
        }

        private func dateSortValue(for node: FileTreeNode) -> Double {
            guard let entry = node.entry,
                  let metadata = parent.metadataByEntryID[entry.id] else { return 0 }
            return metadata.modifiedTimestamp
        }

        private func typeValue(for node: FileTreeNode) -> String {
            if node.isDirectory {
                return AppLocalization().string("文件夹")
            }
            guard let entry = node.entry,
                  let metadata = parent.metadataByEntryID[entry.id] else {
                return AppLocalization().string("文件")
            }
            return metadata.type
        }

        // MARK: NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return rootNodes.count
            }
            guard let node = item as? FileTreeNode else { return 0 }
            return node.children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                return rootNodes[index]
            }
            guard let node = item as? FileTreeNode else { return rootNodes[index] }
            return node.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? FileTreeNode else { return false }
            return node.isDirectory && !node.children.isEmpty
        }

        // MARK: NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileTreeNode else { return nil }
            let localization = AppLocalization()

            switch tableColumn?.identifier.rawValue {
            case "name":
                return makeNameCell(for: node, localization: localization)
            case "size":
                let value: String
                if node.isDirectory {
                    value = "—"
                } else if let entry = node.entry, let metadata = parent.metadataByEntryID[entry.id] {
                    value = metadata.size
                } else {
                    value = "—"
                }
                return makeTextCell(value)
            case "date":
                let value: String
                if node.isDirectory {
                    value = "—"
                } else if let entry = node.entry, let metadata = parent.metadataByEntryID[entry.id] {
                    value = metadata.modifiedDate
                } else {
                    value = "—"
                }
                return makeTextCell(value)
            case "type":
                let value: String
                if node.isDirectory {
                    value = localization.string("文件夹")
                } else if let entry = node.entry, let metadata = parent.metadataByEntryID[entry.id] {
                    value = metadata.type
                } else {
                    value = localization.string("文件")
                }
                return makeTextCell(value)
            default:
                return makeTextCell("—")
            }
        }

        private func makeNameCell(for node: FileTreeNode, localization: AppLocalization) -> NSView {
            let container = NSTableCellView()
            let textField = NSTextField(labelWithString: node.name)
            textField.usesSingleLineMode = true
            textField.maximumNumberOfLines = 1
            textField.lineBreakMode = .byTruncatingMiddle
            textField.toolTip = node.fullPath
            if node.isPendingRemoved {
                textField.attributedStringValue = NSAttributedString(
                    string: node.name,
                    attributes: [
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
                textField.setAccessibilityLabel(node.name + localization.string("（待移除）"))
            } else {
                textField.setAccessibilityLabel(node.name)
            }
            textField.translatesAutoresizingMaskIntoConstraints = false

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            let isNestedArchive = node.entry.map { parent.nestedArchiveEntryIDs.contains($0.id) } ?? false
            if node.isDirectory {
                imageView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: localization.string("文件夹"))
            } else if isNestedArchive {
                // Show archive box icon for entries that are themselves archives
                imageView.image = NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: localization.string("嵌套压缩包"))
                imageView.contentTintColor = .controlAccentColor
            } else {
                let fileExtension = (node.name as NSString).pathExtension
                if fileExtension.isEmpty {
                    imageView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: localization.string("文件"))
                } else {
                    let icon = UTType(filenameExtension: fileExtension)
                        .map { NSWorkspace.shared.icon(for: $0) }
                        ?? NSImage(systemSymbolName: "doc", accessibilityDescription: localization.string("文件"))
                    if let icon {
                        let resized = icon.copy() as? NSImage ?? icon
                        resized.size = NSSize(width: 16, height: 16)
                        imageView.image = resized
                    }
                }
            }
            if imageView.image?.size != NSSize(width: 16, height: 16) {
                imageView.image?.size = NSSize(width: 16, height: 16)
            }

            container.addSubview(imageView)
            container.addSubview(textField)
            container.textField = textField

            var constraints = [
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                textField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ]

            if let badge = node.pendingBadge {
                let badgeField = NSTextField(labelWithString: badge)
                badgeField.font = .systemFont(ofSize: 9, weight: .semibold)
                badgeField.textColor = .controlAccentColor
                badgeField.lineBreakMode = .byClipping
                badgeField.setContentCompressionResistancePriority(.required, for: .horizontal)
                badgeField.setContentHuggingPriority(.required, for: .horizontal)
                badgeField.setAccessibilityLabel(badge)
                badgeField.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(badgeField)
                constraints += [
                    textField.trailingAnchor.constraint(lessThanOrEqualTo: badgeField.leadingAnchor, constant: -6),
                    badgeField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
                    badgeField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                ]
            } else {
                constraints.append(textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2))
            }
            NSLayoutConstraint.activate(constraints)

            return container
        }

        private func makeTextCell(_ value: String) -> NSView {
            // Wrap in NSTableCellView with a centerY constraint so the size /
            // date / type columns sit vertically centered in the 24pt row instead
            // of hugging the top edge (a bare NSTextField returned as a cell view
            // is top-aligned by NSOutlineView).
            let container = NSTableCellView()
            let field = NSTextField(labelWithString: value)
            field.usesSingleLineMode = true
            field.maximumNumberOfLines = 1
            field.lineBreakMode = .byTruncatingMiddle
            field.toolTip = value
            field.setAccessibilityLabel(value)
            field.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(field)
            container.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            return container
        }

        func outlineView(_ outlineView: NSOutlineView, accessibilityLabelForItem item: Any) -> String? {
            guard let node = item as? FileTreeNode else { return nil }
            let localization = AppLocalization()
            let typeValue: String
            let sizeValue: String
            if node.isDirectory {
                typeValue = localization.string("文件夹")
                sizeValue = "—"
            } else if let entry = node.entry, let metadata = parent.metadataByEntryID[entry.id] {
                typeValue = metadata.type
                sizeValue = metadata.size
            } else {
                typeValue = localization.string("文件")
                sizeValue = "—"
            }
            return localization.format("%@，%@，%@", node.name, sizeValue, typeValue)
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outline = notification.object as? NSOutlineView else { return }
            let selectedRow = outline.selectedRow
            guard selectedRow >= 0,
                  let node = outline.item(atRow: selectedRow) as? FileTreeNode else {
                selectedNode = nil
                parent.selection = nil
                parent.onFolderSelectionChange?(nil)
                return
            }
            selectedNode = node
            parent.selection = node.entry?.id
            parent.onFolderSelectionChange?(node.isDirectory ? node.fullPath : nil)
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            return true
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard let item = notification.userInfo?["NSObject"] as? FileTreeNode else { return }
            expandedPaths.insert(item.fullPath)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard let item = notification.userInfo?["NSObject"] as? FileTreeNode else { return }
            expandedPaths.remove(item.fullPath)
        }

        // MARK: Double-Click / Nested Archive

        @objc func outlineViewDoubleClicked(_ sender: Any?) {
            guard let outline = sender as? NSOutlineView else { return }
            let clickedRow = outline.clickedRow
            guard clickedRow >= 0,
                  let node = outline.item(atRow: clickedRow) as? FileTreeNode else { return }
            if let entry = node.entry, parent.nestedArchiveEntryIDs.contains(entry.id) {
                parent.onOpenNestedArchive?(entry.id)
            } else if node.isDirectory {
                if outline.isItemExpanded(node) {
                    outline.collapseItem(node)
                } else {
                    outline.expandItem(node)
                }
            } else if let entry = node.entry {
                parent.onOpenFile?(entry.id)
            }
        }

        // MARK: Context Menu

        private var contextNode: FileTreeNode? {
            if let outline = outlineView, outline.clickedRow >= 0 {
                return outline.item(atRow: outline.clickedRow) as? FileTreeNode
            }
            return selectedNode
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            if let outline = outlineView, outline.clickedRow >= 0, outline.selectedRow != outline.clickedRow {
                outline.selectRowIndexes(IndexSet(integer: outline.clickedRow), byExtendingSelection: false)
            }
            let localization = AppLocalization()
            let node = contextNode
            let hasSelection = node != nil
            let isFile = node.map { !$0.isDirectory } ?? false
            let isNested = node?.entry.map { parent.nestedArchiveEntryIDs.contains($0.id) } ?? false
            let noSelection = localization.string("需要先选中文件")
            let proSuffix = LicenseManager.shared.isProLicensed ? "" : " · Pro"

            for item in menu.items {
                switch item.action {
                case #selector(contextOpen(_:)):
                    // Opening a regular file is Pro; opening a nested archive is free.
                    let openIsPro = isFile && !isNested
                    item.title = localization.string("打开") + (openIsPro ? proSuffix : "")
                    item.isEnabled = hasSelection && (isFile || isNested)
                    item.toolTip = item.isEnabled ? nil
                        : hasSelection ? localization.string("此文件夹无法直接打开")
                        : noSelection
                case #selector(contextExtract(_:)):
                    item.title = localization.string("解压选中") + proSuffix
                    item.isEnabled = hasSelection && parent.canExtract && !parent.isExtracting
                    item.toolTip = item.isEnabled ? nil
                        : !hasSelection ? noSelection
                        : parent.isExtracting ? localization.string("正在解压缩…")
                        : localization.string("此格式不支持解压缩")
                case #selector(contextRename(_:)):
                    let renamableEntry = node?.entry != nil
                    item.title = localization.string("重命名…") + proSuffix
                    item.isEnabled = hasSelection && renamableEntry && parent.canEdit
                    item.toolTip = item.isEnabled ? nil
                        : !hasSelection ? noSelection
                        : !renamableEntry ? localization.string("暂不支持直接重命名文件夹")
                        : localization.string("此格式为只读，不支持编辑")
                case #selector(contextDelete(_:)):
                    let deletableEntry = node?.entry != nil
                    item.title = localization.string("移除") + proSuffix
                    item.isEnabled = hasSelection && deletableEntry && parent.canEdit
                    item.toolTip = item.isEnabled ? nil
                        : !hasSelection ? noSelection
                        : !deletableEntry ? localization.string("暂不支持直接移除文件夹")
                        : localization.string("此格式为只读，不支持编辑")
                case #selector(contextCopyPath(_:)):
                    item.isEnabled = hasSelection
                    item.toolTip = item.isEnabled ? nil : noSelection
                default:
                    break
                }
            }
        }

        @objc func contextOpen(_ sender: Any?) {
            guard let node = contextNode, let entry = node.entry else { return }
            if parent.nestedArchiveEntryIDs.contains(entry.id) {
                parent.onOpenNestedArchive?(entry.id)
            } else if !node.isDirectory {
                parent.onOpenFile?(entry.id)
            }
        }

        @objc func contextExtract(_ sender: Any?) {
            if let node = contextNode, node.isDirectory {
                parent.onExtractFolder?(node.fullPath)
            } else {
                parent.onExtractSelected?()
            }
        }

        @objc func contextRename(_ sender: Any?) {
            parent.onRename?()
        }

        @objc func contextDelete(_ sender: Any?) {
            parent.onDelete?()
        }

        @objc func contextCopyPath(_ sender: Any?) {
            guard let node = contextNode else { return }
            parent.onCopyPath?(node.fullPath)
        }

        // MARK: Sorting

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = outlineView.sortDescriptors.first,
                  let column = TreeSortColumn(rawValue: descriptor.key ?? "") else { return }
            sortState.column = column
            sortState.ascending = descriptor.ascending
            let selectedPath = selectedNode?.fullPath
            sortNodes(&rootNodes)
            outlineView.reloadData()
            for path in expandedPaths {
                if let item = nodeByPath[path] {
                    outlineView.expandItem(item)
                }
            }
            // reloadData() clears the selection (and outlineViewSelectionDidChange
            // would nil out the model's selection); restore it so sorting does not
            // drop the inspector/status-bar context. Key on fullPath/nodeByPath so
            // synthetic entry-less directories (nil entry) are restored too.
            if let selectedPath, let node = nodeByPath[selectedPath] {
                var row = outlineView.row(forItem: node)
                if row < 0 {
                    expandAncestors(of: node, in: outlineView)
                    row = outlineView.row(forItem: node)
                }
                if row >= 0 {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outlineView.scrollRowToVisible(row)
                }
            }
        }

        // MARK: Drag Source (drag-out to Finder)

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let node = item as? FileTreeNode else { return nil }
            // 合成目录（zip 无显式目录条目，由文件路径隐含）entry 为 nil，
            // 但目录拖出只依赖 fullPath + isDirectory，不依赖 entry。
            guard node.entry != nil || node.isDirectory else { return nil }
            let provider = NSFilePromiseProvider(fileType: fileTypeIdentifier(for: node), delegate: self)
            provider.userInfo = EntryDragInfo(
                id: node.entry?.id,
                name: node.name,
                isDirectory: node.isDirectory,
                fullPath: node.fullPath
            )
            return provider
        }

        private func fileTypeIdentifier(for node: FileTreeNode) -> String {
            let ext = (node.name as NSString).pathExtension
            return UTType(filenameExtension: ext)?.identifier ?? UTType.data.identifier
        }

        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
            draggedNodes = draggedItems.compactMap { $0 as? FileTreeNode }
        }

        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            draggedNodes = []
        }

        // MARK: Drop Target (drag-in + internal move)

        private func isInternalDrag(_ info: NSDraggingInfo, outlineView: NSOutlineView) -> Bool {
            (info.draggingSource as? NSView) === outlineView
        }

        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            if isInternalDrag(info, outlineView: outlineView) {
                guard parent.canEdit, !draggedNodes.isEmpty else { return [] }
                if let target = item as? FileTreeNode {
                    guard target.isDirectory else { return [] }
                    // Disallow dropping a folder into itself or its own subtree.
                    for node in draggedNodes where node.isDirectory {
                        if target.fullPath == node.fullPath || target.fullPath.hasPrefix(node.fullPath + "/") {
                            return []
                        }
                    }
                    return .move
                }
                return .move
            }
            guard parent.canEdit else { return [] }
            if info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
                return .copy
            }
            return []
        }

        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            let destinationFolder = (item as? FileTreeNode)?.fullPath
            if isInternalDrag(info, outlineView: outlineView) {
                let nodes = draggedNodes
                draggedNodes = []
                guard !nodes.isEmpty else { return false }
                for node in nodes {
                    moveNode(node, toFolder: destinationFolder)
                }
                return true
            }
            guard let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], !urls.isEmpty else { return false }
            // 拖入的是压缩包 → 打开它，而不是作为文件添加进当前归档。
            // 投递 openArchiveURL（RootWindowView 监听并打开），与 Finder
            // 双击/拖入欢迎页行为一致。
            if let firstArchive = urls.first(where: { parent.onIsSupportedArchive?($0) ?? false }) {
                NotificationCenter.default.post(name: .openArchiveURL, object: firstArchive)
                return true
            }
            parent.onAddFiles?(urls, destinationFolder)
            return true
        }

        private func moveNode(_ node: FileTreeNode, toFolder destinationFolder: String?) {
            let prefix = destinationFolder.map { $0.hasSuffix("/") ? $0 : $0 + "/" } ?? ""
            if let entry = node.entry {
                let sourcePath = entry.displayPath.hasSuffix("/")
                    ? String(entry.displayPath.dropLast())
                    : entry.displayPath
                let destinationPath = prefix + node.name
                parent.onMoveEntry?(sourcePath, destinationPath)
            } else if node.isDirectory {
                // Synthetic folder: move every descendant file entry.
                let sourcePrefix = node.fullPath + "/"
                moveDescendantFiles(of: node, sourcePrefix: sourcePrefix, destinationPrefix: prefix + node.name + "/")
            }
        }

        private func moveDescendantFiles(of node: FileTreeNode, sourcePrefix: String, destinationPrefix: String) {
            for child in node.children {
                if let entry = child.entry, !child.isDirectory {
                    let sourcePath = entry.displayPath.hasSuffix("/")
                        ? String(entry.displayPath.dropLast())
                        : entry.displayPath
                    let relative = sourcePath.hasPrefix(sourcePrefix)
                        ? String(sourcePath.dropFirst(sourcePrefix.count))
                        : child.name
                    parent.onMoveEntry?(sourcePath, destinationPrefix + relative)
                }
                if child.isDirectory {
                    moveDescendantFiles(of: child, sourcePrefix: sourcePrefix, destinationPrefix: destinationPrefix)
                }
            }
        }

        // MARK: NSFilePromiseProviderDelegate (drag-out write)

        nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
            (filePromiseProvider.userInfo as? EntryDragInfo)?.name ?? "file"
        }

        nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo destinationDirectoryURL: URL, completionHandler: @escaping (Error?) -> Void) {
            guard let info = filePromiseProvider.userInfo as? EntryDragInfo else {
                completionHandler(NSError(domain: "MacUnzip", code: 1))
                return
            }
            let completion = PromiseCompletion(completionHandler)
            let fileName = info.name
            Task { @MainActor [weak self] in
                if info.isDirectory {
                    guard let materializeFolder = self?.parent.onMaterializeFolder else {
                        completion.call(NSError(domain: "MacUnzip", code: 2))
                        return
                    }
                    let stagingDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent("MacUnzip_drag_\(UUID().uuidString)", isDirectory: true)
                    do {
                        try FileManager.default.createDirectory(
                            at: stagingDir,
                            withIntermediateDirectories: true,
                            attributes: [.posixPermissions: 0o700]
                        )
                        let folderURL = try await materializeFolder(info.fullPath, stagingDir)
                        // destinationDirectoryURL 可能已是文件夹同名路径，去重
                        var destDir = destinationDirectoryURL
                        if destDir.lastPathComponent == folderURL.lastPathComponent {
                            destDir = destDir.deletingLastPathComponent()
                        }
                        let target = destDir.appendingPathComponent(folderURL.lastPathComponent)
                        Task.detached(priority: .userInitiated) {
                            do {
                                try FileManager.default.copyItem(at: folderURL, to: target)
                                try? FileManager.default.removeItem(at: stagingDir)
                                completion.call(nil)
                            } catch {
                                try? FileManager.default.removeItem(at: stagingDir)
                                completion.call(error)
                            }
                        }
                    } catch {
                        try? FileManager.default.removeItem(at: stagingDir)
                        completion.call(error)
                    }
                    return
                }
                guard let materialize = self?.parent.onMaterializeEntry,
                      let entryID = info.id else {
                    completion.call(NSError(domain: "MacUnzip", code: 2))
                    return
                }
                materialize(entryID) { result in
                    switch result {
                    case .success(let materialized):
                        let materializedURL = materialized.file
                        let stagingRoot = materialized.stagingRoot
                        // The copy can be multi-GB; run it off the main thread so
                        // the UI stays responsive during the drag-out write.
                        Task.detached(priority: .userInitiated) {
                            // destinationDirectoryURL 可能已是 fileName 同名路径
                            // （Finder 把 promise 目标解析为同名文件/目录时），
                            // 此时不再拼 fileName，直接作为目标目录。
                            var destDir = destinationDirectoryURL
                            if destDir.lastPathComponent == fileName {
                                destDir = destDir.deletingLastPathComponent()
                            }
                            var destination = destDir.appendingPathComponent(fileName)
                            do {
                                var counter = 2
                                while FileManager.default.fileExists(atPath: destination.path) {
                                    let base = (fileName as NSString).deletingPathExtension
                                    let ext = (fileName as NSString).pathExtension
                                    let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
                                    destination = destinationDirectoryURL.appendingPathComponent(newName)
                                    counter += 1
                                }
                                try FileManager.default.copyItem(at: materializedURL, to: destination)
                                try? FileManager.default.removeItem(at: stagingRoot)
                                completion.call(nil)
                            } catch {
                                // A failed mid-copy (e.g. disk full) can leave a
                                // corrupt partial file we created; remove it. But
                                // if the copy failed because `destination` already
                                // exists, another process created it in the gap
                                // between our fileExists check and the copy — that
                                // file is not ours, so leave it untouched.
                                let nsError = error as NSError
                                let destinationAlreadyExists = nsError.domain == NSCocoaErrorDomain
                                    && nsError.code == NSFileWriteFileExistsError
                                if !destinationAlreadyExists {
                                    try? FileManager.default.removeItem(at: destination)
                                }
                                try? FileManager.default.removeItem(at: stagingRoot)
                                completion.call(error)
                            }
                        }
                    case .failure(let error):
                        completion.call(error)
                    }
                }
            }
        }
    }
}

// MARK: - Delete-Capturing Outline View

/// An outline view that forwards Delete/Backspace key presses to a removal action
/// while preserving standard behaviour for every other key (including arrow-key
/// expand/collapse navigation). Also supports Cmd+Down Arrow to open nested archives.
private final class DeleteCapturingOutlineView: NSOutlineView {
    var deleteAction: (() -> Void)?
    var renameAction: (() -> Void)?
    var openNestedAction: (() -> Void)?
    var canOpenNested: (() -> Bool)?
    var canEdit: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        let characters = event.charactersIgnoringModifiers ?? ""
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, characters == "\u{F701}" {
            if selectedRow >= 0, canOpenNested?() == true {
                openNestedAction?()
                return
            }
        }
        if characters == "\u{7f}" || characters == "\u{f728}" {
            if selectedRow >= 0, canEdit?() == true {
                deleteAction?()
                return
            }
        }
        if characters == "\r" || characters == "\u{03}" {
            if selectedRow >= 0, canEdit?() == true {
                renameAction?()
                return
            }
        }
        super.keyDown(with: event)
    }
}
