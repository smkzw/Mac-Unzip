public struct ArchiveCapabilityRegistry: Sendable {
    private let snapshots: [ArchiveFormat: ArchiveCapabilitySnapshot]

    /// 运行时发现原则：provider 能力必须按真实运行时发现和验证；不能把设计矩阵直接当作已安装能力。
    public static let productionBaseline = ArchiveCapabilityRegistry(snapshots: [
        .zip: .init(
            actions: [.list, .read, .preview, .create, .update],
            primaryProvider: .minizipNG,
            unavailableReasons: [
                .split: .notYetImplemented,
                .test: .notYetImplemented,
                .repair: .notYetImplemented,
            ]
        ),
        .sevenZip: .init(
            actions: [.list, .read, .preview],
            primaryProvider: .sevenZZ,
            unavailableReasons: [
                .create: .notYetImplemented,
                .update: .notYetImplemented,
                .split: .notYetImplemented,
                .test: .notYetImplemented,
                .repair: .unsupportedByProvider,
            ]
        ),
        .tar: .init(
            actions: [.list, .read, .preview, .create],
            primaryProvider: .libarchive,
            unavailableReasons: [
                .update: .unsupportedByProvider,
                .test: .notYetImplemented,
            ]
        ),
        .gzip: .init(
            actions: [.read, .create],
            primaryProvider: .libarchive,
            unavailableReasons: [
                .update: .unsupportedByProvider,
                .test: .notYetImplemented,
            ]
        ),
        .bzip2: .init(
            actions: [.read, .create],
            primaryProvider: .libarchive,
            unavailableReasons: [
                .update: .unsupportedByProvider,
                .test: .notYetImplemented,
            ]
        ),
        .xz: .init(
            actions: [.read, .create],
            primaryProvider: .libarchive,
            unavailableReasons: [
                .update: .unsupportedByProvider,
                .test: .notYetImplemented,
            ]
        ),
        .zstandard: .init(
            actions: [.read, .create],
            primaryProvider: .libarchive,
            unavailableReasons: [
                .update: .unsupportedByProvider,
                .test: .notYetImplemented,
            ]
        ),
        .rar: .init(
            actions: [.list, .read, .preview],
            primaryProvider: .sevenZZ,
            unavailableReasons: [
                .create: .externalProviderNotValidated,
                .update: .externalProviderNotValidated,
                .test: .notYetImplemented,
                .repair: .unsupportedByProvider,
            ]
        ),
        .dmg: .init(
            actions: [.list, .read, .preview],
            primaryProvider: .sevenZZ,
            unavailableReasons: [.create: .formatReadOnly, .update: .formatReadOnly]
        ),
        .iso: .init(
            actions: [.list, .read, .preview],
            primaryProvider: .sevenZZ,
            unavailableReasons: [.create: .formatReadOnly, .update: .formatReadOnly]
        ),
    ])

    public init(snapshots: [ArchiveFormat: ArchiveCapabilitySnapshot]) {
        self.snapshots = snapshots
    }

    public func snapshot(format: ArchiveFormat) -> ArchiveCapabilitySnapshot {
        snapshots[format] ?? .init(actions: [], primaryProvider: nil, unavailableReasons: [:])
    }

    /// Runtime discovery: register 7z capabilities as available only when the
    /// system 7zz binary was discovered and validated. Otherwise the 7z snapshot
    /// exposes no actions so the UI can prompt to install 7zz.
    public func withSevenZipAvailable(_ available: Bool) -> Self {
        var copy = snapshots
        if available {
            copy[.sevenZip] = .init(
                actions: [.list, .read, .preview, .create],
                primaryProvider: .sevenZZ,
                unavailableReasons: [
                    .update: .notYetImplemented,
                    .split: .notYetImplemented,
                    .test: .notYetImplemented,
                    .repair: .unsupportedByProvider,
                ]
            )
        } else {
            copy[.sevenZip] = .init(
                actions: [],
                primaryProvider: nil,
                unavailableReasons: [
                    .list: .externalProviderNotValidated,
                    .read: .externalProviderNotValidated,
                    .preview: .externalProviderNotValidated,
                    .create: .externalProviderNotValidated,
                    .update: .notYetImplemented,
                ]
            )
        }
        return .init(snapshots: copy)
    }

    /// Runtime discovery: register RAR capabilities as available only when the
    /// system 7zz binary was discovered and validated. Otherwise the RAR snapshot
    /// exposes no actions so the UI can prompt to install 7zz.
    public func withRARAvailable(_ available: Bool) -> Self {
        var copy = snapshots
        if available {
            copy[.rar] = Self.productionBaseline.snapshot(format: .rar)
        } else {
            copy[.rar] = .init(
                actions: [],
                primaryProvider: nil,
                unavailableReasons: [
                    .list: .externalProviderNotValidated,
                    .read: .externalProviderNotValidated,
                    .preview: .externalProviderNotValidated,
                    .create: .externalProviderNotValidated,
                    .update: .externalProviderNotValidated,
                ]
            )
        }
        return .init(snapshots: copy)
    }

    /// Runtime discovery: register DMG capabilities as available only when the
    /// system 7zz binary was discovered and validated. DMG is strictly read-only;
    /// creation and update are always unavailable (format is read-only by design).
    /// When 7zz is missing the UI shows: "需要安装 7zz 以支持此格式".
    public func withDMGAvailable(_ available: Bool) -> Self {
        var copy = snapshots
        if available {
            copy[.dmg] = Self.productionBaseline.snapshot(format: .dmg)
        } else {
            copy[.dmg] = .init(
                actions: [],
                primaryProvider: nil,
                unavailableReasons: [
                    .list: .externalProviderNotValidated,
                    .read: .externalProviderNotValidated,
                    .preview: .externalProviderNotValidated,
                    .create: .formatReadOnly,
                    .update: .formatReadOnly,
                ]
            )
        }
        return .init(snapshots: copy)
    }

    /// Runtime discovery: register ISO capabilities as available only when the
    /// system 7zz binary was discovered and validated. ISO is strictly read-only;
    /// creation and update are always unavailable (format is read-only by design).
    /// When 7zz is missing the UI shows: "需要安装 7zz 以支持此格式".
    public func withISOAvailable(_ available: Bool) -> Self {
        var copy = snapshots
        if available {
            copy[.iso] = Self.productionBaseline.snapshot(format: .iso)
        } else {
            copy[.iso] = .init(
                actions: [],
                primaryProvider: nil,
                unavailableReasons: [
                    .list: .externalProviderNotValidated,
                    .read: .externalProviderNotValidated,
                    .preview: .externalProviderNotValidated,
                    .create: .formatReadOnly,
                    .update: .formatReadOnly,
                ]
            )
        }
        return .init(snapshots: copy)
    }

    /// Runtime discovery: gate RAR creation on whether the external RARLAB rar
    /// provider is available (binary validated + license confirmed). When false,
    /// creation is marked as externalProviderNotValidated; reading via 7zz is
    /// unaffected.
    public func withRARCreateAvailable(_ available: Bool) -> Self {
        var copy = snapshots
        let existing = copy[.rar]
        if available {
            var actions = existing?.actions ?? []
            actions.insert(.create)
            actions.insert(.test)
            var reasons = existing?.unavailableReasons ?? [:]
            reasons.removeValue(forKey: .create)
            reasons.removeValue(forKey: .test)
            reasons[.update] = .notYetImplemented
            copy[.rar] = .init(
                actions: actions,
                primaryProvider: .rarLab,
                unavailableReasons: reasons
            )
        } else {
            // Preserve read capabilities from 7zz but mark creation unavailable
            var actions = existing?.actions ?? []
            actions.remove(.create)
            actions.remove(.test)
            var reasons = existing?.unavailableReasons ?? [:]
            reasons[.create] = .externalProviderNotValidated
            reasons[.test] = .externalProviderNotValidated
            copy[.rar] = .init(
                actions: actions,
                primaryProvider: existing?.primaryProvider,
                unavailableReasons: reasons
            )
        }
        return .init(snapshots: copy)
    }
}
