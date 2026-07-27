import AppKit
import UniformTypeIdentifiers
import ArchiveDomain
import SwiftUI

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
    static func build(from entries: [ArchiveEntry]) -> [FileTreeNode] {
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
    let entries: [ArchiveEntry]
    let metadataByEntryID: [ArchiveEntryID: ArchiveEntryMetadata]
    @Binding var selection: ArchiveEntryID?
    var nestedArchiveEntryIDs: Set<ArchiveEntryID> = []
    var onDelete: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onOpenNestedArchive: ((ArchiveEntryID) -> Void)? = nil
    var onOpenFile: ((ArchiveEntryID) -> Void)? = nil
    var onExtractSelected: (() -> Void)? = nil
    var onCopyPath: ((String) -> Void)? = nil

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
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsMultipleSelection = false
        outline.delegate = context.coordinator
        outline.dataSource = context.coordinator
        outline.indentationPerLevel = 16
        outline.rowHeight = 24

        outline.selectionHighlightStyle = .regular
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.outlineViewDoubleClicked(_:))

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = localization.string("名称")
        nameColumn.width = 300
        nameColumn.minWidth = 120
        outline.addTableColumn(nameColumn)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = localization.string("大小")
        sizeColumn.width = 120
        sizeColumn.minWidth = 60
        outline.addTableColumn(sizeColumn)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = localization.string("修改日期")
        dateColumn.width = 180
        dateColumn.minWidth = 100
        outline.addTableColumn(dateColumn)

        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.title = localization.string("类型")
        typeColumn.width = 100
        typeColumn.minWidth = 60
        outline.addTableColumn(typeColumn)

        outline.outlineTableColumn = nameColumn

        // Enable sorting on all columns
        for column in outline.tableColumns {
            let sortDescriptor = NSSortDescriptor(key: column.identifier.rawValue, ascending: true)
            column.sortDescriptorPrototype = sortDescriptor
        }

        let menu = NSMenu()
        menu.delegate = context.coordinator
        let openItem = NSMenuItem(title: localization.string("打开"), action: #selector(Coordinator.contextOpen(_:)), keyEquivalent: "")
        openItem.target = context.coordinator
        menu.addItem(openItem)
        let extractItem = NSMenuItem(title: localization.string("解压选中"), action: #selector(Coordinator.contextExtract(_:)), keyEquivalent: "")
        extractItem.target = context.coordinator
        menu.addItem(extractItem)
        menu.addItem(.separator())
        let renameItem = NSMenuItem(title: localization.string("重命名"), action: #selector(Coordinator.contextRename(_:)), keyEquivalent: "")
        renameItem.target = context.coordinator
        menu.addItem(renameItem)
        let deleteItem = NSMenuItem(title: localization.string("移除"), action: #selector(Coordinator.contextDelete(_:)), keyEquivalent: "")
        deleteItem.target = context.coordinator
        menu.addItem(deleteItem)
        menu.addItem(.separator())
        let copyPathItem = NSMenuItem(title: localization.string("拷贝路径"), action: #selector(Coordinator.contextCopyPath(_:)), keyEquivalent: "")
        copyPathItem.target = context.coordinator
        menu.addItem(copyPathItem)
        outline.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let outline = scrollView.documentView as? NSOutlineView else { return }

        let entriesChanged = context.coordinator.lastEntries != entries

        if entriesChanged {
            context.coordinator.lastEntries = entries

            // Capture expanded paths before reload
            let oldExpandedPaths = context.coordinator.expandedPaths

            context.coordinator.rebuildTree()
            context.coordinator.sortNodes(&context.coordinator.rootNodes)
            outline.reloadData()

            // Reapply sort indicators
            let descriptor = NSSortDescriptor(key: context.coordinator.sortState.column.rawValue, ascending: context.coordinator.sortState.ascending)
            outline.sortDescriptors = [descriptor]

            // Restore expansion state
            for path in oldExpandedPaths {
                if let item = context.coordinator.nodeByPath[path] {
                    outline.expandItem(item)
                }
            }
        }

        // Restore selection (always, since selection may change independently)
        if let selected = selection {
            if let node = context.coordinator.nodeByEntryID[selected] {
                let row = outline.row(forItem: node)
                if row >= 0 && outline.selectedRow != row {
                    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outline.scrollRowToVisible(row)
                }
            }
        } else if outline.selectedRow >= 0 {
            outline.deselectAll(nil)
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        var parent: ArchiveListView
        var rootNodes: [FileTreeNode] = []
        var nodeByPath: [String: FileTreeNode] = [:]
        var nodeByEntryID: [ArchiveEntryID: FileTreeNode] = [:]
        var expandedPaths: Set<String> = []
        var sortState = TreeSortState()
        var lastEntries: [ArchiveEntry] = []

        init(parent: ArchiveListView) {
            self.parent = parent
            super.init()
            rebuildTree()
        }

        func rebuildTree() {
            rootNodes = FileTreeBuilder.build(from: parent.entries)
            sortNodes(&rootNodes)

            nodeByPath = [:]
            nodeByEntryID = [:]
            indexNodes(rootNodes)
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
            return parseByteCount(from: metadata.size)
        }

        private func dateSortValue(for node: FileTreeNode) -> String {
            guard let entry = node.entry,
                  let metadata = parent.metadataByEntryID[entry.id] else { return "" }
            return metadata.modifiedDate
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

        /// Parses a byte count from formatted size strings like "8.4 MB (8,796,293 字节)"
        private func parseByteCount(from formatted: String) -> Double {
            // Try to extract the number in parentheses (exact byte count)
            if let openParen = formatted.lastIndex(of: "("),
               let closeParen = formatted.lastIndex(of: ")") {
                let inner = formatted[formatted.index(after: openParen)..<closeParen]
                let digits = inner.filter { $0.isNumber }
                if let value = Double(digits) {
                    return value
                }
            }
            // Fallback: parse the leading number and unit
            let parts = formatted.split(separator: " ")
            guard let numberPart = parts.first, let value = Double(numberPart) else { return 0 }
            let unit = parts.count > 1 ? String(parts[1]).uppercased() : ""
            switch unit {
            case "KB": return value * 1024
            case "MB": return value * 1024 * 1024
            case "GB": return value * 1024 * 1024 * 1024
            default: return value
            }
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
            textField.setAccessibilityLabel(node.name)
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

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])

            return container
        }

        private func makeTextCell(_ value: String) -> NSView {
            let field = NSTextField(labelWithString: value)
            field.usesSingleLineMode = true
            field.maximumNumberOfLines = 1
            field.lineBreakMode = .byTruncatingMiddle
            field.toolTip = value
            field.setAccessibilityLabel(value)
            return field
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
                parent.selection = nil
                return
            }
            parent.selection = node.entry?.id
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

        private var selectedNode: FileTreeNode? {
            guard let outline = parent.selection.flatMap({ nodeByEntryID[$0] }) else { return nil }
            return outline
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            let hasSelection = parent.selection != nil
            let node = selectedNode
            let isFile = node.map { !$0.isDirectory } ?? false
            let isNested = node?.entry.map { parent.nestedArchiveEntryIDs.contains($0.id) } ?? false

            for item in menu.items {
                switch item.action {
                case #selector(contextOpen(_:)):
                    item.isEnabled = hasSelection && (isFile || isNested)
                case #selector(contextExtract(_:)):
                    item.isEnabled = hasSelection
                case #selector(contextRename(_:)):
                    item.isEnabled = hasSelection
                case #selector(contextDelete(_:)):
                    item.isEnabled = hasSelection
                case #selector(contextCopyPath(_:)):
                    item.isEnabled = hasSelection
                default:
                    break
                }
            }
        }

        @objc func contextOpen(_ sender: Any?) {
            guard let node = selectedNode, let entry = node.entry else { return }
            if parent.nestedArchiveEntryIDs.contains(entry.id) {
                parent.onOpenNestedArchive?(entry.id)
            } else if !node.isDirectory {
                parent.onOpenFile?(entry.id)
            }
        }

        @objc func contextExtract(_ sender: Any?) {
            parent.onExtractSelected?()
        }

        @objc func contextRename(_ sender: Any?) {
            parent.onRename?()
        }

        @objc func contextDelete(_ sender: Any?) {
            parent.onDelete?()
        }

        @objc func contextCopyPath(_ sender: Any?) {
            guard let node = selectedNode else { return }
            parent.onCopyPath?(node.fullPath)
        }

        // MARK: Sorting

        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = outlineView.sortDescriptors.first,
                  let column = TreeSortColumn(rawValue: descriptor.key ?? "") else { return }
            sortState.column = column
            sortState.ascending = descriptor.ascending
            sortNodes(&rootNodes)
            outlineView.reloadData()
            for path in expandedPaths {
                if let item = nodeByPath[path] {
                    outlineView.expandItem(item)
                }
            }
        }
    }
}

// MARK: - Delete-Capturing Outline View

/// An outline view that forwards Delete/Backspace key presses to a removal action
/// while preserving standard behaviour for every other key (including arrow-key
/// expand/collapse navigation). Also supports Cmd+O to open nested archives.
private final class DeleteCapturingOutlineView: NSOutlineView {
    var deleteAction: (() -> Void)?
    var renameAction: (() -> Void)?
    var openNestedAction: (() -> Void)?
    var canOpenNested: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        let characters = event.charactersIgnoringModifiers ?? ""
        if event.modifierFlags.contains(.command), characters == "o" {
            if selectedRow >= 0, canOpenNested?() == true {
                openNestedAction?()
                return
            }
        }
        if characters == "\u{7f}" || characters == "\u{f728}" {
            if selectedRow >= 0 {
                deleteAction?()
                return
            }
        }
        if characters == "\r" || characters == "\u{03}" {
            if selectedRow >= 0 {
                renameAction?()
                return
            }
        }
        super.keyDown(with: event)
    }
}
