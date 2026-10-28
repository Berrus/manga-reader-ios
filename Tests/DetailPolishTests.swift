import XCTest
@testable import MangaReader

final class DetailPolishTests: XCTestCase {
    func testReaderErrorsBecomeActionable() {
        XCTAssertTrue(ReaderErrorView.friendly("Extension error: The server returned HTTP 403.").contains("refused"))
        XCTAssertTrue(ReaderErrorView.friendly("The server returned HTTP 404.").contains("wasn't found"))
        XCTAssertTrue(ReaderErrorView.friendly("The server returned HTTP 429.").contains("limiting"))
        XCTAssertTrue(ReaderErrorView.friendly("The server returned HTTP 503.").contains("trouble"))
        XCTAssertEqual(ReaderErrorView.friendly("Extension error: Something odd"), "Something odd")
    }

    func testSourceIdsGetReadableNames() {
        XCTAssertEqual(SourceRegistry.fallbackName("pb.AsuraScans"), "Asura Scans")
        XCTAssertEqual(SourceRegistry.fallbackName("pb.Atsumaru"), "Atsumaru")
        XCTAssertEqual(SourceRegistry.fallbackName("mangadex"), "MangaDex")
        XCTAssertEqual(SourceRegistry.fallbackName("komga.123"), "Personal server")
    }

    #if !APP_STORE
    func testLongSeriesKeepEveryChapter() async throws {
        let script = """
        var source = {Fake: {async getChapters(m) {
          var a = [];
          for (var i = 0; i < 2500; i++) a.push({chapterId: 'c' + i, title: 'T' + i, chapNum: i, sourceManga: {mangaId: m.mangaId}});
          return a;
        }}};
        """
        let fake = try PaperbackSource(info: PaperbackExtensionInfo(id: "Fake", name: "Fake", version: "1"), script: script)
        let rows = try await fake.chapters(for: MangaSummary(id: "m", title: "M"))
        XCTAssertEqual(rows.count, 2500)
    }
    #endif
}
