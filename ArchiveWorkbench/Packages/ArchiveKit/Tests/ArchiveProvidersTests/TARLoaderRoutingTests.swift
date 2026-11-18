import Foundation
import Testing

/// Historical package-level TAR fixture helpers remain in TARArchiveProviderTests.
/// Real ArchiveDocumentLoader.open coverage lives in AppUnitTests/TARDocumentLoaderTests.
@Suite("TAR loader routing marker")
struct TARLoaderRoutingTests {
    @Test("loader coverage moved to AppUnitTests")
    func marker() {
        #expect(true)
    }
}
