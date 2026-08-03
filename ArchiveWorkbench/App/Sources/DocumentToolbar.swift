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

    private var editDisabledHelp: String {
        if model.isNestedSession {
            return AppLocalization().string("嵌套压缩包为只读，请返回上级编辑")
        }
        return model.canAdd
            ? AppLocalization().string("需要先选中文件")
            : AppLocalization().string("此格式为只读，不支持编辑")
    }

    private func editHelp(enabled: Bool, _ enabledText: String) -> String {
        enabled ? AppLocalization().string(enabledText) : editDisabledHelp
    }

    private func proLabel(_ text: String) -> String {
        LicenseManager.shared.isProLicensed
            ? AppLocalization().string(text)
            : AppLocalization().string(text) + " · Pro"
    }

    private var saveHelp: String {
        if model.isNestedSession {
            return AppLocalization().string("请先返回上级压缩包再保存")
        }
        return model.hasUnsavedChanges
            ? AppLocalization().string("保存修改")
            : AppLocalization().string("没有需要保存的更改")
    }

    private var extractHelp: String {
        if model.isExtracting {
            return AppLocalization().string("正在解压缩…")
        }
        return model.canExtract
            ? AppLocalization().string("解压缩全部内容")
            : AppLocalization().string("此格式不支持解压缩")
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                archiveTitle

                if model.isNestedSession {
                    breadcrumbBar
                }
            }
            .padding(.leading, 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AppLocalization().string("归档工具栏"))
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 16) {
                toolbarButton("保存", symbol: "square.and.arrow.down", help: saveHelp, enabled: model.hasUnsavedChanges && !model.isNestedSession) {
                    Task { await model.saveArchive() }
                }
                toolbarButton("添加", symbol: "plus", help: model.canAdd ? "向压缩包添加文件" : "此格式为只读，不支持添加", enabled: model.canAdd, pro: true) {
                    onAdd()
                }
                toolbarButton("解压缩全部", symbol: "arrow.down.to.line", help: extractHelp, enabled: model.canExtract && !model.isExtracting, pro: true) {
                    onExtract()
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            viewToggle
        }
        ToolbarItem(placement: .primaryAction) {
            operationMenu
        }
        ToolbarItem(placement: .primaryAction) {
            ToolbarSearchField(
                text: $model.searchText,
                placeholder: "搜索"
            )
            .frame(minWidth: 100, maxWidth: 180)
            .padding(.trailing, 4)
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
        .frame(maxWidth: 160, alignment: .leading)
        .help(model.documentTitle)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            model.hasUnsavedChanges
                ? AppLocalization().format("%@，%ld 项，尚未保存", model.documentTitle, model.visibleEntries.count)
                : AppLocalization().format("%@，%ld 项", model.documentTitle, model.visibleEntries.count)
        )
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
        .frame(maxWidth: 160)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("嵌套路径")
    }

    private var viewToggle: some View {
        HStack(spacing: 8) {
            viewToggleButton(mode: .list, symbol: "list.bullet", label: "列表视图")
            viewToggleButton(mode: .media, symbol: "square.grid.2x2", label: "媒体预览")
        }
        .help(AppLocalization().string("切换列表/媒体视图"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("视图切换")
    }

    private func viewToggleButton(mode: ArchiveViewMode, symbol: String, label: String) -> some View {
        let isActive = model.viewMode == mode
        return Button {
            model.viewMode = mode
        } label: {
            Label(AppLocalization().string(label), systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.callout.weight(isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(AppLocalization().string(label))
        .accessibilityIdentifier(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .help(AppLocalization().string(label))
    }

    private var operationMenu: some View {
        Menu {
            Button {
                NotificationCenter.default.post(name: .createArchiveRequest, object: nil)
            } label: {
                Label(proLabel("新建压缩包"), systemImage: "externaldrive.badge.plus")
            }

            Divider()

            Button { onExtractSelected() } label: {
                Label(proLabel("解压选中"), systemImage: "arrow.down.doc")
            }
            .disabled(!model.canExtractSelected)
            .help(model.canExtractSelected ? AppLocalization().string("解压选中的文件") : AppLocalization().string("需要先选中文件"))

            Divider()

            Button { onRemove() } label: {
                Label(proLabel("移除"), systemImage: "minus")
            }
            .disabled(!model.canRemoveSelectedEntry)
            .help(editHelp(enabled: model.canRemoveSelectedEntry, "移除选中文件"))

            Button { onRename() } label: {
                Label(proLabel("重命名…"), systemImage: "pencil")
            }
            .disabled(!model.canRenameSelectedEntry)
            .help(editHelp(enabled: model.canRenameSelectedEntry, "重命名选中文件"))

            Button { onReplace() } label: {
                Label(proLabel("替换"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!model.canReplaceSelectedEntry)
            .help(editHelp(enabled: model.canReplaceSelectedEntry, "替换选中文件"))

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
        .accessibilityLabel(AppLocalization().string("更多操作"))
        .accessibilityIdentifier("操作")
    }

    private func toolbarButton(_ label: String, symbol: String, help: String, enabled: Bool, pro: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Label(AppLocalization().string(label), systemImage: symbol)
                    .font(.callout.weight(.medium))
                if pro && !LicenseManager.shared.isProLicensed {
                    Text("Pro")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.trailing, 12)
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(pro && !LicenseManager.shared.isProLicensed
            ? AppLocalization().string(label) + " Pro"
            : AppLocalization().string(label))
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
        field.cell?.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.refusesFirstResponder = false
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
            guard let field, field.window?.isKeyWindow == true else { return }
            field.window?.makeFirstResponder(field)
        }
    }
}
