import AppKit
import SwiftUI

/// Reports the NSWindow hosting the represented view, so callers can target
/// window-specific behavior (e.g. accessibility notifications) correctly in
/// multi-window sessions.
struct WindowCaptureView: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowReportingView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowReportingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}
