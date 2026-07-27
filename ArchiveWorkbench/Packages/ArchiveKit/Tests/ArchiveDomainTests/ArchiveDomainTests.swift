import Testing
@testable import ArchiveDomain

@Test func rawPathBytesRemainSeparateFromDisplayName() {
    let bytes = ArchivePathBytes([0x83, 0x65, 0x83, 0x58, 0x83, 0x67])
    let entry = ArchiveEntry(id: .init(), rawPath: bytes, displayPath: "テスト")
    #expect(entry.rawPath == bytes)
    #expect(entry.displayPath == "テスト")
}

@Test func userFacingErrorsAreDistinct() {
    #expect(ArchiveError.passwordRequired != .wrongPassword)
    #expect(ArchiveError.wrongPassword != .unsupportedEncryption)
}
