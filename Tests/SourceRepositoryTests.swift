import XCTest
@testable import MangaReader

final class SourceRepositoryTests: XCTestCase {
    func testEmptyVersionOneCatalogDecodes() throws {
        let data = Data(#"{"version":1,"sources":[]}"#.utf8)
        XCTAssertEqual(try SourceRepositoryIndex.decode(data).sources.count, 0)
    }

    func testUnsupportedVersionAndAndroidCatalogAreRejected() {
        XCTAssertThrowsError(try SourceRepositoryIndex.decode(Data(#"{"version":2,"sources":[]}"#.utf8)))
        XCTAssertThrowsError(try SourceRepositoryIndex.decode(Data(#"[{"apk":"extension.apk"}]"#.utf8)))
    }

    func testCatalogCannotContainExecutableScript() {
        let json = #"{"version":1,"sources":[{"id":"example.source","name":"Example","version":"1","hosts":["example.com"],"script":"alert(1)"}]}"#
        XCTAssertThrowsError(try SourceRepositoryIndex.decode(Data(json.utf8)))
    }
}
