import ArchiveProviders
import Foundation

enum ExternalCreateNameStagingError: Error, Equatable, Sendable {
    case enumeratorUnavailable(URL)
    case symlinkRejected(URL)
    case unexpectedItem(URL)
}

/// Stages renamed inputs for external 7z/RAR CLIs that key off basename.
/// Prefers hardlinks; on cross-volume / link failure falls back to copy.
/// Any failure after the staging directory is created removes `MacUnzip_create_names_*`.
enum ExternalCreateNameStaging {
    typealias FileOp = @Sendable (URL, URL) throws -> Void

    static func defaultLinkItem(source: URL, destination: URL) throws {
        try FileManager.default.linkItem(at: source, to: destination)
    }

    static func defaultCopyItem(source: URL, destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    static func prepare(
        inputs: [ArchiveCreationInput],
        linker: FileOp? = nil,
        copier: FileOp? = nil
    ) throws -> (urls: [URL], cleanup: () -> Void) {
        let linkOp = linker ?? defaultLinkItem
        let copyOp = copier ?? defaultCopyItem
        let needsStaging = inputs.contains {
            $0.archiveRootName != $0.sourceURL.lastPathComponent
        }
        guard needsStaging else {
            return (inputs.map(\.sourceURL), {})
        }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacUnzip_create_names_\(UUID().uuidString)", isDirectory: true)
        let cleanup: () -> Void = { try? FileManager.default.removeItem(at: staging) }

        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            var staged: [URL] = []
            for input in inputs {
                let destination = staging.appendingPathComponent(
                    input.archiveRootName,
                    isDirectory: CreationInputMerging.isDirectory(input.sourceURL)
                )
                if CreationInputMerging.isDirectory(input.sourceURL) {
                    try stageTree(
                        from: input.sourceURL,
                        to: destination,
                        linker: linkOp,
                        copier: copyOp
                    )
                } else {
                    try linkOrCopyFile(
                        from: input.sourceURL,
                        to: destination,
                        linker: linkOp,
                        copier: copyOp
                    )
                }
                staged.append(destination)
            }
            return (staged, cleanup)
        } catch {
            cleanup()
            throw error
        }
    }

    private static func linkOrCopyFile(
        from source: URL,
        to destination: URL,
        linker: FileOp,
        copier: FileOp
    ) throws {
        do {
            try linker(source, destination)
        } catch {
            try copier(source, destination)
        }
    }

    /// Recursively stage a directory tree. Uses resolved real paths so `/var` vs
    /// `/private/var` cannot drop every child. Does not skip package contents.
    /// Symlinks are rejected (existing security policy), never silently ignored.
    static func stageTree(
        from source: URL,
        to destination: URL,
        linker: FileOp,
        copier: FileOp
    ) throws {
        let root = source.resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        final class EnumerationFailure: @unchecked Sendable {
            var error: Error?
        }
        let failure = EnumerationFailure()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .isPackageKey
            ],
            options: [], // include .app/.bundle package descendants
            errorHandler: { _, error in
                failure.error = error
                return false // abort enumeration
            }
        ) else {
            throw ExternalCreateNameStagingError.enumeratorUnavailable(root)
        }

        let rootPath = root.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        while let item = enumerator.nextObject() as? URL {
            if let error = failure.error {
                throw error
            }

            let values = try item.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey
            ])
            if values.isSymbolicLink == true {
                throw ExternalCreateNameStagingError.symlinkRejected(item)
            }

            let itemPath = item.resolvingSymlinksInPath().standardizedFileURL.path
            guard itemPath.hasPrefix(prefix) else {
                throw ExternalCreateNameStagingError.unexpectedItem(item)
            }
            let relative = String(itemPath.dropFirst(prefix.count))
            guard !relative.isEmpty else { continue }
            let target = destination.appendingPathComponent(relative)

            if values.isDirectory == true {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } else if values.isRegularFile == true {
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try linkOrCopyFile(from: item, to: target, linker: linker, copier: copier)
            } else {
                throw ExternalCreateNameStagingError.unexpectedItem(item)
            }
        }

        if let error = failure.error {
            throw error
        }
    }
}
