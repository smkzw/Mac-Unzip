import AppKit
import SwiftUI

struct AccessibleGroupHost<Content: View>: NSViewRepresentable {
    let identifier: String
    let role: NSAccessibility.Role
    let content: Content

    init(identifier: String, role: NSAccessibility.Role = .group, @ViewBuilder content: () -> Content) {
        self.identifier = identifier
        self.role = role
        self.content = content()
    }

    func makeNSView(context: Context) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.isTransparent = true
        box.titlePosition = .noTitle
        box.setAccessibilityRole(role)
        box.setAccessibilityIdentifier(identifier)
        box.setAccessibilityLabel(AppLocalization().string(identifier))

        let hostingView = NSHostingView(rootView: content)
        hostingView.setAccessibilityRole(.group)
        hostingView.setAccessibilityLabel(
            AppLocalization().format("%@内容", AppLocalization().string(identifier))
        )
        hostingView.setAccessibilityIdentifier("\(identifier)_content")
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        box.contentView = hostingView
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: box.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        return box
    }

    func updateNSView(_ box: NSBox, context: Context) {
        (box.contentView as? NSHostingView<Content>)?.rootView = content
    }
}
