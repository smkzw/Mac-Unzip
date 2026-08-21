import Testing
import ArchiveFixtures
@testable import ArchiveSecurity

@Test(arguments: [
    ("/absolute", ArchiveSecurityError.absolutePath),
    ("../escape", ArchiveSecurityError.parentTraversal),
    ("safe/../escape", ArchiveSecurityError.parentTraversal),
    ("", ArchiveSecurityError.emptyComponent),
    ("/", ArchiveSecurityError.absolutePath),
    ("safe/", ArchiveSecurityError.emptyComponent),
    ("safe//file", ArchiveSecurityError.emptyComponent),
    ("safe\0file", ArchiveSecurityError.controlCharacter),
    ("safe/line\nfile", ArchiveSecurityError.controlCharacter),
    ("safe/\u{7f}file", ArchiveSecurityError.controlCharacter),
])
func rejectsStructurallyUnsafePaths(_ path: String, _ expectedError: ArchiveSecurityError) {
    #expect(throws: expectedError) {
        try ArchivePathPolicy().validate(path)
    }
}

@Test(arguments: [
    "plain/file.txt",
    "中文/资料.txt",
    "日本語/資料.txt",
    "العربية/ملف.txt",
    "emoji/📦.txt",
])
func acceptsStructurallySafePaths(_ path: String) throws {
    try ArchivePathPolicy().validate(path)
}

@Test
func fixturesPreserveRequiredMultilingualAndWindowsConflictCases() {
    #expect(MaliciousPaths.multilingual == [
        "中文/资料.txt",
        "日本語/資料.txt",
        "العربية/ملف.txt",
        "emoji/📦.txt",
    ])
    #expect(MaliciousPaths.windowsConflicts == ["CON", "LPT¹", "name. ", "Readme", "README"])
}

@Test
func multilingualFixturesAreStructurallySafe() throws {
    for path in MaliciousPaths.multilingual {
        try ArchivePathPolicy().validate(path)
    }
}

@Test
func componentLengthLimitCountsScalarsNotBytes() throws {
    // macOS (APFS) allows 255 Unicode scalars per component. A byte-based
    // limit falsely rejects long CJK names (3 UTF-8 bytes per character).
    let policy = ArchivePathPolicy()
    try policy.validate("dir/" + String(repeating: "a", count: 255))
    try policy.validate("dir/" + String(repeating: "测", count: 255)) // 765 UTF-8 bytes
    #expect(throws: ArchiveSecurityError.componentTooLong) {
        try policy.validate("dir/" + String(repeating: "a", count: 256))
    }
    #expect(throws: ArchiveSecurityError.componentTooLong) {
        try policy.validate("dir/" + String(repeating: "测", count: 256))
    }
}
