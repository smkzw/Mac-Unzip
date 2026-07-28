import SwiftUI

struct ArchiveSidebarView: View {
    @Bindable var model: AppModel
    let onExtract: () -> Void
    let onAdd: () -> Void
    let onOpenRecent: (URL) -> Void

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

    private var quickActionsSection: some View {
        Section {
            Button {
                onAdd()
            } label: {
                Label(AppLocalization().string("添加文件"), systemImage: "plus")
            }
            .disabled(!model.canAdd)

            Button {
                onExtract()
            } label: {
                Label(AppLocalization().string("解压缩全部"), systemImage: "arrow.down.to.line")
            }
            .disabled(!model.canExtract || model.isExtracting)
        } header: {
            Label("快捷操作", systemImage: "bolt")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recentSection: some View {
        Section {
            let maxCount = UserDefaults.standard.object(forKey: SettingsKeys.recentArchivesCount) == nil
                ? 10
                : UserDefaults.standard.integer(forKey: SettingsKeys.recentArchivesCount)
            let recent = RecentArchivesManager.shared.recentURLs
            if maxCount == 0 {
                EmptyView()
            } else if recent.isEmpty {
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
