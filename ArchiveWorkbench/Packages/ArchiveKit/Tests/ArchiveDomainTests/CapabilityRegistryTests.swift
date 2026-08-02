import Testing
@testable import ArchiveDomain

@Test(arguments: [ArchiveFormat.zip])
func writableFormatsExposeCreation(_ format: ArchiveFormat) {
    let snapshot = ArchiveCapabilityRegistry.productionBaseline.snapshot(format: format)

    #expect(snapshot.actions.contains(.create))
    #expect(snapshot.primaryProvider != nil)
}

@Test
func sevenZipIsReadOnlyByDesign() {
    let snapshot = ArchiveCapabilityRegistry.productionBaseline.snapshot(format: .sevenZip)

    #expect(snapshot.actions.contains(.list))
    #expect(snapshot.actions.contains(.read))
    #expect(snapshot.actions.contains(.preview))
    #expect(!snapshot.actions.contains(.create))
    #expect(!snapshot.actions.contains(.update))
    #expect(snapshot.primaryProvider == .sevenZZ)
    #expect(snapshot.unavailableReasons[.create] == .notYetImplemented)
}

@Test
func sevenZipAvailabilityIsGatedOnRuntimeDiscovery() {
    let baseline = ArchiveCapabilityRegistry.productionBaseline

    let available = baseline.withSevenZipAvailable(true)
    #expect(available.snapshot(format: .sevenZip).actions.contains(.read))
    #expect(available.snapshot(format: .sevenZip).primaryProvider == .sevenZZ)

    let missing = baseline.withSevenZipAvailable(false)
    #expect(missing.snapshot(format: .sevenZip).actions.isEmpty)
    #expect(missing.snapshot(format: .sevenZip).primaryProvider == nil)
    #expect(missing.snapshot(format: .sevenZip).unavailableReasons[.read] == .externalProviderNotValidated)
    // Other formats are unaffected by 7z discovery state.
    #expect(missing.snapshot(format: .zip).actions.contains(.create))
}

@Test
func dmgIsReadOnly() {
    let snapshot = ArchiveCapabilityRegistry.productionBaseline.snapshot(format: .dmg)

    #expect(snapshot.actions.contains(.list))
    #expect(snapshot.actions.contains(.read))
    #expect(snapshot.actions.contains(.preview))
    #expect(!snapshot.actions.contains(.create))
    #expect(!snapshot.actions.contains(.update))
}

@Test
func rarCreateRequiresValidatedExternalProvider() {
    let snapshot = ArchiveCapabilityRegistry.productionBaseline.snapshot(format: .rar)

    #expect(!snapshot.actions.contains(.create))
    #expect(snapshot.unavailableReasons[.create] == .externalProviderNotValidated)
}

@Test
func productionBaselineMatchesTheCapabilityMatrix() {
    let expected: [ArchiveFormat: ArchiveCapabilitySnapshot] = [
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
    ]

    for format in ArchiveFormat.allCases {
        #expect(ArchiveCapabilityRegistry.productionBaseline.snapshot(format: format) == expected[format])
    }
}

@Test
func validatedRARLABReturnsAnIndependentRegistry() {
    let baseline = ArchiveCapabilityRegistry.productionBaseline
    let validated = baseline.withRARCreateAvailable(true)

    #expect(!baseline.snapshot(format: .rar).actions.contains(.create))
    #expect(validated.snapshot(format: .rar).actions.contains(.create))
    #expect(validated.snapshot(format: .rar).actions.contains(.test))
    #expect(!validated.snapshot(format: .rar).actions.contains(.update))
    #expect(validated.snapshot(format: .rar).primaryProvider == .rarLab)
    #expect(validated.snapshot(format: .rar).unavailableReasons == [
        .update: .notYetImplemented,
        .repair: .unsupportedByProvider,
    ])
}

@Test
func noFormatClaimsUnimplementedIntegrityActions() {
    let registry = ArchiveCapabilityRegistry.productionBaseline

    for format in ArchiveFormat.allCases {
        let snapshot = registry.snapshot(format: format)
        #expect(!snapshot.actions.contains(.test),
            "\(format) should not claim .test")
        #expect(!snapshot.actions.contains(.repair),
            "\(format) should not claim .repair")
    }
}

@Test
func missingFormatReturnsAnEmptySnapshot() {
    let registry = ArchiveCapabilityRegistry(snapshots: [:])

    #expect(registry.snapshot(format: .zip) == .init(
        actions: [],
        primaryProvider: nil,
        unavailableReasons: [:]
    ))
}
