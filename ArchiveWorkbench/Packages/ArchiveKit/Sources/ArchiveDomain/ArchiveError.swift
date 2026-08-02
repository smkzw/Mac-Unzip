public enum ArchiveError: String, Error, Codable, Sendable {
    case unsupportedFormat, unsupportedMethod, passwordRequired, wrongPassword
    case unsupportedEncryption, corruptedArchive, missingVolume, unsafePath
    case resourceLimit, sourceChanged, helperFailed, ioError
    /// An external provider binary required for this format (e.g. 7zz for 7z)
    /// is not installed or failed runtime validation.
    case providerNotInstalled
}
