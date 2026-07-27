import SwiftUI

extension Notification.Name {
    static let focusArchiveSearch = Notification.Name("focusArchiveSearch")
}

struct DocumentToolbar: ToolbarContent {
    @Bindable var model: AppModel
    let onAdd: () -> Void
    let onExtract: () -> Void
    let onExtractSelected: () -> Void
    let onRemove: () -> Void
    let onRename: () -> Void
    let onReplace: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                archiveTitle

                if model.isNestedSession {
                    breadcrumbBar
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AppLocalization().string("归档工具栏"))
        }

        ToolbarItemGroup(placement: .primaryAction) {
            toolbarButton("添加", symbol: "plus", help: "向压缩包添加文件", enabled: model.canAdd) {
                onAdd()
            }
            toolbarButton("解压缩", symbol: "arrow.down.to.line", help: "解压缩全部内容", enabled: model.canExtract && !model.isExtracting) {
                onExtract()
            }

            viewToggle

            operationMenu

            ToolbarSearchField(
                text: $model.searchText,
                placeholder: "搜索"
            )
            .frame(minWidth: 120, maxWidth: 220)
        }
    }

    private var archiveTitle: some View {
        HStack(spacing: 6) {
            Text(model.documentTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            if model.hasUnsavedChanges {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
                    .help(AppLocalization().string("尚未保存"))
            }
            Text(AppLocalization().format("%ld 项", model.visibleEntries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 200, alignment: .leading)
        .help(model.documentTitle)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization().format("%@，%ld 项", model.documentTitle, model.visibleEntries.count))
        .accessibilityIdentifier("归档标题")
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 2) {
            Button {
                model.navigateBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .help(AppLocalization().string("返回上一层压缩包"))
            .accessibilityLabel(AppLocalization().string("返回"))

            ForEach(Array(model.breadcrumbSegments.enumerated()), id: \.element.id) { index, segment in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                if index < model.breadcrumbSegments.count - 1 {
                    Button {
                        model.navigateToBreadcrumb(index: segment.id)
                    } label: {
                        Text(segment.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .help(AppLocalization().format("跳转到 %@", segment.title))
                } else {
                    Text(segment.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: 200)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("嵌套路径")
    }

    private var viewToggle: some View {
        Picker("视图", selection: $model.viewMode) {
            Image(systemName: "list.bullet")
                .tag(ArchiveViewMode.list)
                .accessibilityLabel(AppLocalization().string("列表视图"))
            Image(systemName: "square.grid.2x2")
                .tag(ArchiveViewMode.media)
                .accessibilityLabel(AppLocalization().string("媒体预览"))
        }
        .pickerStyle(.segmented)
        .frame(width: 68)
        .labelsHidden()
        .help(AppLocalization().string("切换列表/媒体视图"))
        .accessibilityIdentifier("视图切换")
    }

    private var operationMenu: some View {
        Menu {
            Button {
                NotificationCenter.default.post(name: .createArchiveRequest, object: nil)
            } label: {
                Label(AppLocalization().string("新建压缩包"), systemImage: "archivebox.badge.plus")
            }

            Divider()

            Button { onExtractSelected() } label: {
                Label(AppLocalization().string("解压选中"), systemImage: "arrow.down.doc")
            }
            .disabled(!model.canExtractSelected)
            .help(AppLocalization().string("需要先选中文件"))

            Divider()

            Button { onRemove() } label: {
                Label(AppLocalization().string("移除"), systemImage: "minus")
            }
            .disabled(!model.canRemoveSelectedEntry)
            .help(AppLocalization().string("需要先选中文件"))

            Button { onRename() } label: {
                Label(AppLocalization().string("重命名"), systemImage: "pencil")
            }
            .disabled(!model.canRenameSelectedEntry)
            .help(AppLocalization().string("需要先选中文件"))

            Button { onReplace() } label: {
                Label(AppLocalization().string("替换"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!model.canReplaceSelectedEntry)
            .help(AppLocalization().string("需要先选中文件"))

            Divider()

            Button { model.inspectorVisible.toggle() } label: {
                Label(
                    AppLocalization().string(model.inspectorVisible ? "隐藏信息" : "显示信息"),
                    systemImage: "info.circle"
                )
            }

            Button { model.sidebarVisible.toggle() } label: {
                Label(
                    AppLocalization().string(model.sidebarVisible ? "隐藏侧栏" : "显示侧栏"),
                    systemImage: "sidebar.left"
                )
            }

            Divider()

            Menu {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button {
                        model.appearanceMode = mode
                    } label: {
                        if model.appearanceMode == mode {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                }
            } label: {
                Label(AppLocalization().string("外观"), systemImage: "circle.lefthalf.filled")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 30)
        .help(AppLocalization().string("更多操作"))
        .accessibilityLabel(AppLocalization().string("操作"))
        .accessibilityIdentifier("操作")
    }

    private func toolbarButton(_ label: String, symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.callout.weight(.medium))
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(AppLocalization().string(label))
        .accessibilityHint(AppLocalization().string(help))
        .accessibilityIdentifier(label)
        .help(AppLocalization().string(help))
        .disabled(!enabled)
    }
}

private struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = AppLocalization().string(placeholder)
        field.identifier = NSUserInterfaceItemIdentifier("搜索框")
        field.setAccessibilityIdentifier("搜索框")
        field.setAccessibilityLabel(AppLocalization().string("搜索压缩包内容"))
        field.delegate = context.coordinator
        context.coordinator.field = field
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.focusSearch),
            name: .focusArchiveSearch,
            object: nil
        )
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        let localizedPlaceholder = AppLocalization().string(placeholder)
        if field.placeholderString != localizedPlaceholder { field.placeholderString = localizedPlaceholder }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        weak var field: NSSearchField?
        init(text: Binding<String>) { self.text = text }

        deinit { NotificationCenter.default.removeObserver(self) }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                guard !text.wrappedValue.isEmpty else { return false }
                text.wrappedValue = ""
                (control as? NSSearchField)?.stringValue = ""
                return true
            }
            return false
        }

        @MainActor @objc func focusSearch() {
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }
    }
}
