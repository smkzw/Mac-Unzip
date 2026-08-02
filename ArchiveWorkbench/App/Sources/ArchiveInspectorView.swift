import ArchiveDomain
import SwiftUI

struct ArchiveInspectorView: View {
    let metadata: ArchiveEntryMetadata?
    var folder: FolderSelectionInfo?

    var body: some View {
        AccessibleGroupHost(identifier: "归档信息检查器") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("信息")
                        .font(.headline)
                    if let folder {
                        detailRow("类型", value: AppLocalization().string("文件夹"))
                        detailRow("路径", value: folder.path)
                        detailRow("包含项目", value: AppLocalization().format("%ld 项", folder.itemCount))
                    } else {
                        detailRow("类型", value: metadata?.type ?? "—")
                        detailRow("大小", value: metadata?.size ?? "—")
                        detailRow("压缩后大小", value: metadata?.compressedSize ?? "—")
                        detailRow("修改日期", value: metadata?.modifiedDate ?? "—")
                        detailRow("路径", value: metadata?.path ?? "—")
                    }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalization().string(label))
                .font(.callout)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fontWeight(.medium)
            Text(value)
                .font(.callout)
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(2)
                .truncationMode(.middle)
                .help(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
