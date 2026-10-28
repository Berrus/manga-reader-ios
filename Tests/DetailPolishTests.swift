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

final class UpdateRetryTests: XCTestCase {
    func testTransientNetworkErrorsAreRetriedButHTTPErrorsAreNot() {
        XCTAssertTrue(LibraryUpdater.isTransient(URLError(.secureConnectionFailed)))
        XCTAssertTrue(LibraryUpdater.isTransient(URLError(.timedOut)))
        XCTAssertFalse(LibraryUpdater.isTransient(URLError(.badURL)))
        XCTAssertFalse(LibraryUpdater.isTransient(TransportError.http(404)))
        #if !APP_STORE
        XCTAssertTrue(LibraryUpdater.isTransient(PaperbackError.extensionFailed("A TLS error caused the secure connection to fail.")))
        #endif
    }

    func testTLSFailuresReadClearly() {
        XCTAssertTrue(ReaderErrorView.friendly("Extension error: A TLS error caused the secure connection to fail.").contains("secure connection"))
        XCTAssertTrue(ReaderErrorView.friendly("The request timed out.").contains("too long"))
    }
}

#if !APP_STORE
final class PaperbackChapterContextTests: XCTestCase {
    /// Some extensions (Asura Scans) build the chapter address from `chapNum` and `additionalInfo`.
    func testChapterNumberAndExtraInfoReachTheExtension() async throws {
        let script = """
        var source = {Fake: {
          async getChapters(m) { return [{chapterId: 'c9', title: '', chapNum: 142, additionalInfo: {early_access: 'true'}, sourceManga: m}]; },
          async getChapterDetails(c) {
            return {id: c.chapterId, mangaId: c.sourceManga.mangaId,
                    pages: ['https://cdn.example/' + c.sourceManga.mangaId + '/' + c.chapNum + '/' + (c.additionalInfo ? c.additionalInfo.early_access : 'none') + '.jpg']};
          }
        }};
        """
        let fake = try PaperbackSource(info: PaperbackExtensionInfo(id: "Fake", name: "Fake", version: "1"), script: script)
        let chapters = try await fake.chapters(for: MangaSummary(id: "series-x", title: "S"))
        let pages = try await fake.pages(for: chapters[0])
        XCTAssertEqual(pages.first?.url, "https://cdn.example/series-x/142/true.jpg")
    }
}
#endif
