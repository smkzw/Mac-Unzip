public enum ArchiveFormat: String, Codable, Sendable, CaseIterable {
    case zip, sevenZip, tar, gzip, bzip2, xz, zstandard, rar, dmg, iso
}
