import Foundation

/// Stable provider identifiers used by redacted capability evidence.
public enum ProviderID: String, Codable, Sendable {
    case sevenZip
    case bundledHelper
    case externalExecutable
    case diskImage
    case quickLook
    case securityScopedBookmark
}

/// A deliberately small, secret-free record suitable for checked-in evidence.
public struct ProviderSpikeResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pass
        case fail
        case capabilityDisabled
    }

    public let provider: ProviderID
    public let version: String
    public let status: Status
    public let commandArgumentHash: String
    public let outputSHA256: String?
    public let failureCode: String?

    public init(
        provider: ProviderID,
        version: String,
        status: Status,
        commandArgumentHash: String,
        outputSHA256: String?,
        failureCode: String?
    ) {
        self.provider = provider
        self.version = version
        self.status = status
        self.commandArgumentHash = commandArgumentHash
        self.outputSHA256 = outputSHA256
        self.failureCode = failureCode
    }
}
