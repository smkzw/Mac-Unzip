import SwiftUI

struct ArchiveSidebarView: View {
    @Bindable var model: AppModel
    @AppStorage(SettingsKeys.recentArchivesCount) private var recentArchivesCount = 10
    let onExtract: () -> Void
    let onAdd: () -> Void
    let onOpenRecent: (URL) -> Void
    let onOpen: (() -> Void)?
    let onCreate: (() -> Void)?

    init(
        model: AppModel,
        onExtract: @escaping () -> Void,
        onAdd: @escaping () -> Void,
        onOpenRecent: @escaping (URL) -> Void,
        onOpen: (() -> Void)? = nil,
        onCreate: (() -> Void)? = nil
    ) {
        self.model = model
        self.onExtract = onExtract
        self.onAdd = onAdd
        self.onOpenRecent = onOpenRecent
        self.onOpen = onOpen
        self.onCreate = onCreate
    }

    var body: some View {
        List {
            if model.hasDocument {
                archiveInfoSection
                quickActionsSection
            }
            recentSection
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
    }

    private var archiveInfoSection: some View {
        Section {
            infoRow("格式", value: model.archiveFormatName)
            infoRow("项目数", value: "\(model.documentItemCount)")
            infoRow("文件名", value: model.documentTitle)
        } header: {
            Label("压缩包信息", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var extractHelp: String {
        if model.isExtracting {
            return AppLocalization().string("正在解压缩…")
        }
        return model.canExtract
            ? AppLocalization().string("解压缩全部内容")
            : AppLocalization().string("此格式不支持解压缩")
    }

    private var quickActionsSection: some View {
        Section {
            Button {
                onOpen?()
            } label: {
                Label(AppLocalization().string("打开其他压缩包"), systemImage: "folder")
            }
            .help(AppLocalization().string("打开另一个压缩包"))

            Button {
                onCreate?()
            } label: {
                HStack(spacing: 4) {
                    Label(AppLocalization().string("新建压缩包"), systemImage: "archivebox.badge.plus")
                    if !LicenseManager.shared.isProLicensed { proBadge }
                }
            }
            .help(AppLocalization().string("新建一个压缩包（需要 Pro）"))

            Button {
                onAdd()
            } label: {
                HStack(spacing: 4) {
                    Label(AppLocalization().string("添加文件"), systemImage: "plus")
                    if !LicenseManager.shared.isProLicensed { proBadge }
                }
            }
            .disabled(!model.canAdd)
            .help(model.canAdd ? AppLocalization().string("向压缩包添加文件") : AppLocalization().string("此格式为只读，不支持添加"))

            Button {
                onExtract()
            } label: {
                HStack(spacing: 4) {
                    Label(AppLocalization().string("解压缩全部"), systemImage: "arrow.down.to.line")
                    if !LicenseManager.shared.isProLicensed { proBadge }
                }
            }
            .disabled(!model.canExtract || model.isExtracting)
            .help(extractHelp)
        } header: {
            Label("快捷操作", systemImage: "bolt")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var proBadge: some View {
        Text("Pro")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.purple)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.purple.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var recentSection: some View {
        let maxCount = recentArchivesCount
        let recent = RecentArchivesManager.shared.recentURLs
        if maxCount > 0 {
            Section {
                if recent.isEmpty {
                    Text("暂无最近打开的压缩包")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(recent.prefix(maxCount), id: \.self) { url in
                        Button {
                            onOpenRecent(url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "archivebox")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(url.path)
                    }
                }
            } header: {
                Label("最近打开", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(AppLocalization().string(label))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
