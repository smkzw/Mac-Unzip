import Testing
import ArchiveDomain
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
func renameProposalNeverMutatesRawBytes() {
    let raw = ArchivePathBytes(Array("CON".utf8))

    let proposal = WindowsNamePolicy().proposal(displayPath: "CON", rawPath: raw)

    #expect(proposal.outputPath == "CON_文件")
    #expect(proposal.sourceRawPath == raw)
}
