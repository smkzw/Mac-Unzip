import SwiftUI

/// Shared layout and visual tokens. Prefer system materials/fonts/semantic colors;
/// keep a single accent and quiet spacing hierarchy.
enum UIConstants {
    // MARK: Spacing

    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space6: CGFloat = 6
    static let space8: CGFloat = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32

    static let paddingSmall: CGFloat = space6
    static let paddingMedium: CGFloat = space12
    static let paddingLarge: CGFloat = space32

    // MARK: Layout

    static let defaultWindowWidth: CGFloat = 1180
    static let defaultWindowHeight: CGFloat = 760
    static let statusBarHeight: CGFloat = 36
    static let toolbarHeight: CGFloat = 44

    static let inspectorColumnMinWidth: CGFloat = 260
    static let inspectorColumnIdealWidth: CGFloat = 280
    static let inspectorColumnMaxWidth: CGFloat = 320

    static let welcomeContentMaxWidth: CGFloat = 520
    static let welcomeDropMinHeight: CGFloat = 168
    static let createPanelWidth: CGFloat = 640
    /// Tall enough for empty-state destination + pinned footer without relying on scroll.
    static let createPanelHeight: CGFloat = 640
    static let createDropMinHeight: CGFloat = 112

    static let progressBarWidth: CGFloat = 140
    static let cornerRadius: CGFloat = 12
    static let cornerRadiusSmall: CGFloat = 8

    // MARK: Visual

    /// Single accent — system control accent, not a custom brand gradient.
    static let accent = Color.accentColor
    static let warningOpacity: Double = 0.12
    static let dropFillOpacity: Double = 0.06
    static let hairline = Color.primary.opacity(0.08)

    static let maxProcessStderrBytes: Int = 256 * 1024
    static let standardAnimationDuration: Double = 0.22

    static let captionFontSize: CGFloat = 11
    static let caption2FontSize: CGFloat = 10
    static let calloutFontSize: CGFloat = 13
}

extension Color {
    static let warningBackground: Color = .orange.opacity(UIConstants.warningOpacity)
    static let secondaryText: Color = .secondary
    static let primaryText: Color = .primary
}
