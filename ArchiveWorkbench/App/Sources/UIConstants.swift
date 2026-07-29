import SwiftUI

/// Centralized constants for UI layout, spacing, and styling to avoid magic numbers
/// throughout the codebase. Extracted from ArchiveDocumentView.swift and other locations.
/// 
/// This struct provides consistent values across the application, improving maintainability
/// and theme customization capabilities.
struct UIConstants {
    // MARK: - Spacing
    
    /// Small padding value (6 points)
    static let paddingSmall: CGFloat = 6
    
    /// Medium padding value (12 points)
    static let paddingMedium: CGFloat = 12
    
    /// Large padding value (32 points) used for status bar content
    static let paddingLarge: CGFloat = 32
    
    // MARK: - Layout
    
    /// Default window width (1180 points)
    static let defaultWindowWidth: CGFloat = 1180
    
    /// Default window height (760 points)
    static let defaultWindowHeight: CGFloat = 760
    
    /// Status bar height (38 points)
    static let statusBarHeight: CGFloat = 38
    
    /// Inspector column minimum/ideal/max widths
    static let inspectorColumnMinWidth: CGFloat = 265
    static let inspectorColumnIdealWidth: CGFloat = 280
    static let inspectorColumnMaxWidth: CGFloat = 340
    
    // MARK: - Styling
    
    /// Warning banner background opacity (0.12) meets WCAG AA contrast ratio (~4.5:1)
    static let warningOpacity: Double = 0.12
    
    /// Progress bar fixed width (140 points)
    static let progressBarWidth: CGFloat = 140
    
    // MARK: - Process Limits
    
    /// Maximum stderr buffer size for external processes (256 KB)
    static let maxProcessStderrBytes: Int = 256 * 1024
    
    // MARK: - Animation Durations
    
    /// Standard animation duration in seconds
    static let standardAnimationDuration: Double = 0.25
    
    // MARK: - Typography
    
    /// Caption font size
    static let captionFontSize: CGFloat = 11
    
    /// Caption 2 font size  
    static let caption2FontSize: CGFloat = 9
    
    /// Callout font size
    static let calloutFontSize: CGFloat = 13
}

// MARK: - Color Constants

extension Color {
    /// Warning color with proper accessibility contrast
    static let warningBackground: Color = .orange.opacity(0.12)
    
    /// Secondary text color (system equivalent)
    static let secondaryText: Color = .secondary
    
    /// Primary text color (system equivalent)
    static let primaryText: Color = .primary
}
