import SwiftUI
import MarkdownUI

struct MarkdownPreviewView: View {
    let content: String
    let title: String

    var body: some View {
        ScrollView {
            Markdown(content)
                .markdownTheme(.gitHub)
                .textSelection(.enabled)
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
        }
        .accessibilityIdentifier("Markdown预览")
        .accessibilityLabel("Markdown 预览：\(title)")
    }
}
