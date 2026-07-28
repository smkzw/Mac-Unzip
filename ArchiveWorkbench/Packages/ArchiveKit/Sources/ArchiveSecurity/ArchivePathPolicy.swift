import ArchiveDomain

public enum ArchiveSecurityError: Error, Equatable, Sendable {
    case absolutePath
    case parentTraversal
    case emptyComponent
    case controlCharacter
    case componentTooLong
}

/// Validates only the structural form of an archive member path.
///
/// Filesystem publication must independently enforce descriptor-rooted
/// containment and link safety after extraction.
public struct ArchivePathPolicy: Sendable {
    public init() {}

    public func validate(_ path: String) throws {
        if path.hasPrefix("/") {
            throw ArchiveSecurityError.absolutePath
        }
        if path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) {
            throw ArchiveSecurityError.controlCharacter
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains(where: \.isEmpty) {
            throw ArchiveSecurityError.emptyComponent
        }
        if components.contains("..") {
            throw ArchiveSecurityError.parentTraversal
        }
        if path.hasPrefix("-") {
            throw ArchiveSecurityError.controlCharacter
        }
        if components.contains(".") {
            throw ArchiveSecurityError.emptyComponent
        }
        if components.contains(where: { $0.utf8.count > 255 }) {
            throw ArchiveSecurityError.componentTooLong
        }
    }
}

public struct WindowsNameProposal: Equatable, Sendable {
    public let outputPath: String
    public let sourceRawPath: ArchivePathBytes

    public init(outputPath: String, sourceRawPath: ArchivePathBytes) {
        self.outputPath = outputPath
        self.sourceRawPath = sourceRawPath
    }
}

/// Produces optional output-name suggestions while retaining the source bytes.
public struct WindowsNamePolicy: Sendable {
    public init() {}

    public func proposal(displayPath: String, rawPath: ArchivePathBytes) -> WindowsNameProposal {
        WindowsNameProposal(
            outputPath: displayPath == "CON" ? "CON_文件" : displayPath,
            sourceRawPath: rawPath
        )
    }
}
