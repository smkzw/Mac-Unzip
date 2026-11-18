import Darwin
import Foundation

/// NSFilePromiseProvider write destination + exclusive publish helpers.
///
/// SDK (`NSFilePromiseProvider.h`): `writePromiseToURL` — "Always use the supplied URL."
/// Finder morphologies recorded in TAKEOVER_REPORT v1.1.6:
/// - Directory URL: write `promisedFileName` inside it.
/// - File URL (same-name collision): the supplied URL is already the exact target;
///   do not append again, and do not auto-rename on conflict.
enum FilePromisePublishing {
    struct Destination: Equatable, Sendable {
        /// Exact leaf URL the receiver expects to read.
        var exactURL: URL
    }

    /// Resolve the supplied promise URL to the exact publish target.
    /// File-shaped URLs (`!hasDirectoryPath`) stay exact even if a same-named
    /// directory currently occupies that path — never treat that as a drop folder.
    static func resolveDestination(suppliedURL: URL, promisedFileName: String) -> Destination {
        let fileShaped = !suppliedURL.hasDirectoryPath
        if fileShaped {
            return Destination(exactURL: suppliedURL)
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: suppliedURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return Destination(
                exactURL: suppliedURL.appendingPathComponent(promisedFileName)
            )
        }

        // Directory-contract URL that does not exist yet.
        return Destination(
            exactURL: suppliedURL.appendingPathComponent(promisedFileName)
        )
    }

    /// Publish `source` to the exact destination via owned staging + RENAME_EXCL.
    /// On EEXIST / collision: delete only staging, throw — never alternate names,
    /// never delete the pre-existing destination.
    @discardableResult
    static func exclusivelyPublishItem(
        at source: URL,
        toExactDestination destination: URL
    ) throws -> URL {
        let sourceIsDirectory = isDirectory(source)
        var destinationIsDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: destination.path,
            isDirectory: &destinationIsDirectory
        ) {
            throw CocoaError(
                .fileWriteFileExists,
                userInfo: [NSFilePathErrorKey: destination.path]
            )
        }

        let parent = destination.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(
            ".macunzip-publish-\(UUID().uuidString)",
            isDirectory: sourceIsDirectory
        )
        do {
            try FileManager.default.copyItem(at: source, to: staging)
            let permissions: Int = sourceIsDirectory ? 0o700 : 0o600
            try? FileManager.default.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: staging.path
            )
            try exclusiveRename(from: staging, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Compatibility wrapper used by call sites that already resolved directory + name.
    @discardableResult
    static func exclusivelyPublishItem(
        at source: URL,
        toDirectory directory: URL,
        preferredName: String
    ) throws -> URL {
        try exclusivelyPublishItem(
            at: source,
            toExactDestination: directory.appendingPathComponent(
                preferredName,
                isDirectory: isDirectory(source)
            )
        )
    }

    static func exclusiveRename(from: URL, to: URL) throws {
        let result = from.path.withCString { fromPath in
            to.path.withCString { toPath in
                renamex_np(fromPath, toPath, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [
                NSLocalizedDescriptionKey: String(cString: strerror(code))
            ])
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return url.hasDirectoryPath
            || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
