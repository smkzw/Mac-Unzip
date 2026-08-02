import Darwin
import Foundation

/// Validates that a staging file is a structurally complete ZIP archive before
/// crash recovery renames it over the user's original.
///
/// Recovery only had a `size >= 22` check historically, so a process that died
/// mid-write could leave a partial staging file that recovery would then rename
/// over an intact original — destroying good data. This validator requires a
/// parseable End-Of-Central-Directory record and a fully-present central
/// directory whose entry headers and claimed data fit within the file.
enum ZIPStagingValidator {
    static func isValidArchive(at url: URL) -> Bool {
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var statBuf = stat()
        guard Darwin.fstat(fd, &statBuf) == 0,
              (statBuf.st_mode & S_IFMT) == S_IFREG,
              statBuf.st_size >= 22
        else { return false }
        let fileSize = Int(statBuf.st_size)

        guard let eocdr = locateEOCDR(fd: fd, fileSize: fileSize) else { return false }
        let (entryCount, cdirSize, cdirOffset) = eocdr

        // An empty archive legitimately has an empty central directory at EOF;
        // a non-empty one must point inside the file body.
        if entryCount == 0 {
            return cdirSize == 0
        }
        guard cdirSize > 0,
              cdirOffset >= 0,
              cdirOffset < fileSize,
              cdirOffset + cdirSize <= fileSize
        else { return false }

        return centralDirectoryParses(
            fd: fd,
            entryCount: entryCount,
            cdirOffset: cdirOffset,
            cdirSize: cdirSize,
            fileSize: fileSize
        )
    }

    // MARK: Private

    private static func locateEOCDR(fd: Int32, fileSize: Int) -> (Int, Int, Int)? {
        // EOCDR is 22 bytes minimum; a trailing comment can push it back up to
        // 65535 bytes. Scan backwards for the 0x06054b50 signature.
        let maxBack = min(fileSize, 22 + 65535)
        var buffer = [UInt8](repeating: 0, count: maxBack)
        let start = fileSize - maxBack
        guard pread(fd, &buffer, maxBack, off_t(start)) == maxBack else { return nil }
        for i in stride(from: maxBack - 22, through: 0, by: -1) {
            guard buffer[i] == 0x50, buffer[i + 1] == 0x4b,
                  buffer[i + 2] == 0x05, buffer[i + 3] == 0x06
            else { continue }
            let entryCount = Int(read16(buffer, i + 10))
            let cdirSize = Int(read32(buffer, i + 12))
            let cdirOffset = Int(read32(buffer, i + 16))
            // ZIP64 markers are not produced by our writer; reject rather than
            // guess so recovery falls back to the safe discard path.
            if cdirOffset == 0xFFFF_FFFF || cdirSize == 0xFFFF_FFFF || entryCount == 0xFFFF {
                return nil
            }
            return (entryCount, cdirSize, cdirOffset)
        }
        return nil
    }

    private static func centralDirectoryParses(
        fd: Int32,
        entryCount: Int,
        cdirOffset: Int,
        cdirSize: Int,
        fileSize: Int
    ) -> Bool {
        var cdir = [UInt8](repeating: 0, count: cdirSize)
        guard pread(fd, &cdir, cdirSize, off_t(cdirOffset)) == cdirSize else { return false }

        var offset = 0
        for _ in 0..<entryCount {
            // A central-directory file header is 46 bytes minimum.
            guard offset + 46 <= cdirSize,
                  cdir[offset] == 0x50, cdir[offset + 1] == 0x4b,
                  cdir[offset + 2] == 0x01, cdir[offset + 3] == 0x02
            else { return false }
            let compressedSize = Int(read32(cdir, offset + 20))
            let nameLength = Int(read16(cdir, offset + 28))
            let extraLength = Int(read16(cdir, offset + 30))
            let commentLength = Int(read16(cdir, offset + 32))
            let localHeaderOffset = Int(read32(cdir, offset + 42))
            guard localHeaderOffset >= 0, localHeaderOffset < fileSize else { return false }

            // The entry's compressed data must fit inside the file. Reading the
            // local header tells us where the data actually begins.
            var local = [UInt8](repeating: 0, count: 30)
            guard pread(fd, &local, 30, off_t(localHeaderOffset)) == 30,
                  local[0] == 0x50, local[1] == 0x4b,
                  local[2] == 0x03, local[3] == 0x04
            else { return false }
            let localNameLength = Int(read16(local, 26))
            let localExtraLength = Int(read16(local, 28))
            let dataStart = localHeaderOffset + 30 + localNameLength + localExtraLength
            guard dataStart >= 0, dataStart + compressedSize <= fileSize else { return false }

            offset += 46 + nameLength + extraLength + commentLength
        }
        // The central directory must be exactly consumed — no trailing garbage
        // before the EOCDR.
        return offset == cdirSize
    }

    private static func read16(_ bytes: [UInt8], _ index: Int) -> UInt16 {
        UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }

    private static func read32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
    }
}
