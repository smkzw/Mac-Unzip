import AppKit
import SwiftUI

// MARK: - Pro Feature Definitions

/// Features that require a MacUnzip Pro license.
enum ProFeature: String, CaseIterable, Sendable {
    case extract
    case create
    case edit
    case encrypt
    case openExternal

    /// Short description shown in the upgrade prompt.
    var upgradeDescription: String {
        let localization = AppLocalization()
        switch self {
        case .extract: return localization.string("解压缩文件需要 MacUnzip Pro")
        case .create: return localization.string("创建压缩包需要 MacUnzip Pro")
        case .edit: return localization.string("编辑压缩包（添加、删除、重命名）需要 MacUnzip Pro")
        case .encrypt: return localization.string("加密压缩包需要 MacUnzip Pro")
        case .openExternal: return localization.string("用其他应用打开文件需要先将其解压缩，此功能需要 MacUnzip Pro")
        }
    }
}

// MARK: - License Gate

/// Central gate that checks Pro license status before allowing protected operations.
@MainActor
enum LicenseGate {
    /// Notification posted when a gated action is blocked (UI can observe to show upgrade sheet).
    static let upgradeRequiredNotification = Notification.Name("MacUnzipUpgradeRequired")

    /// Returns true if the user is licensed (action may proceed).
    /// If not licensed, posts an upgrade-required notification with the feature name
    /// and returns false.
    @discardableResult
    static func requirePro(for feature: ProFeature) -> Bool {
        if LicenseManager.shared.isProLicensed {
            return true
        }
        NotificationCenter.default.post(
            name: upgradeRequiredNotification,
            object: nil,
            userInfo: ["feature": feature]
        )
        return false
    }

    /// Non-notifying check — returns license status without side effects.
    static var isProLicensed: Bool {
        LicenseManager.shared.isProLicensed
    }
}
