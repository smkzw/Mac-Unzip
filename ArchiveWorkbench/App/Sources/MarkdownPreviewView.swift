import SwiftUI
import MarkdownUI

struct MarkdownPreviewView: View {
    let content: String
    let title: String

    var body: some View {
        ScrollView {
            Markdown(Self.sanitized(content))
                .markdownTheme(.gitHub)
                .textSelection(.enabled)
                .padding(24)
                .frame(maxWidth: 720, alignment: .leading)
        }
        .accessibilityIdentifier("Markdown预览")
        .accessibilityLabel("Markdown 预览：\(title)")
    }

    /// Archive content is untrusted and the app is not sandboxed: block
    /// anything that would auto-fetch remote content or embed active HTML.
    private static func sanitized(_ markdown: String) -> String {
        var result = markdown
        result = result.replacing(/<\/?(?:script|iframe|object|embed|link|meta|form|input|button)\b[^>]*>/.ignoresCase(), with: "")
        result = result.replacing(/<img\b[^>]*>/.ignoresCase(), with: "")
        result = result.replacing(/!\[([^\]]*)\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)/) { match in
            let url = String(match.2)
            return url.lowercased().hasPrefix("data:image/") ? String(match.0) : String(match.1)
        }
        return result
    }
}
