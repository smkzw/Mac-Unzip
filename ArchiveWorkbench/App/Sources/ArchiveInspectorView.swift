import ArchiveDomain
import SwiftUI

struct ArchiveInspectorView: View {
    let metadata: ArchiveEntryMetadata?

    var body: some View {
        AccessibleGroupHost(identifier: "归档信息检查器") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("信息")
                        .font(.headline)
                    detailRow("类型", value: metadata?.type ?? "—")
                    detailRow("大小", value: metadata?.size ?? "—")
                    detailRow("压缩后大小", value: metadata?.compressedSize ?? "—")
                    detailRow("修改日期", value: metadata?.modifiedDate ?? "—")
                    detailRow("路径", value: metadata?.path ?? "—")
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
