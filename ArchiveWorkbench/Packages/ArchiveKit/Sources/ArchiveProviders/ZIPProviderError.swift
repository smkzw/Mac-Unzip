import ArchiveDomain
import CMinizipBridge

enum ZIPProviderErrorMapper {
    static func archiveError(for status: Int32) -> ArchiveError {
        switch status {
        case AWB_MZ_FORMAT_ERROR, AWB_MZ_CRC_ERROR:
            return .corruptedArchive
        case AWB_MZ_PASSWORD_ERROR:
            return .wrongPassword
        case AWB_MZ_UNSUPPORTED_ERROR:
            return .unsupportedMethod
        case AWB_MZ_MEMORY_ERROR:
            return .resourceLimit
        case AWB_MZ_OPEN_ERROR:
            // minizip-ng returns MZ_OPEN_ERROR when a required split volume
            // (.z01, .z02, ...) is missing from the set.
            return .missingVolume
        case AWB_MZ_IO_ERROR:
            // I/O errors during spanning typically indicate corrupted volume data.
            return .corruptedArchive
        default:
            return .helperFailed
        }
    }
}
