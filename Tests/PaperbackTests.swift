#if !APP_STORE
import XCTest
@testable import MangaReader

final class PaperbackTests: XCTestCase {
    private func source(_ script: String, id: String = "Fake") throws -> PaperbackSource {
        try PaperbackSource(info: PaperbackExtensionInfo(id: id, name: "Fake", version: "1"), script: script)
    }

    // Shaped like a real 0.9 bundle: a global `source` object holding one instance per extension id.
    private let bundle = """
    var source = (function (e) {
      class Fake {
        async initialise() {
          Application.registerInterceptor("i", Application.Selector(this, "interceptRequest"), Application.Selector(this, "interceptResponse"));
        }
        async interceptRequest(r) { r.headers = Object.assign({}, r.headers, {referer: "https://site.example/"}); return r; }
        async interceptResponse(q, r, data) { return data; }
        async getSearchResults(query, metadata) {
          Application.setState("seen", "last");
          return {items: [
            {mangaId: "m1", title: Application.decodeHTMLEntities("A &amp; B " + query.title), imageUrl: "https://cdn.example/c.jpg"},
            {mangaId: "", title: "no id"}
          ], metadata: {page: 2}};
        }
        async getMangaDetails(id) { return {mangaId: id, mangaInfo: {primaryTitle: "T " + id, synopsis: "S", thumbnailUrl: "http://insecure.example/c.jpg"}}; }
        async getChapters(manga) { return [{chapterId: "c1", title: "", chapNum: 3, sourceManga: manga}, {chapterId: "", chapNum: 4}]; }
        async getChapterDetails(chapter) { return {id: chapter.chapterId, mangaId: chapter.sourceManga.mangaId, pages: ["https://cdn.example/1.jpg", "https://cdn.example/2.jpg"]}; }
      }
      e.Fake = new Fake();
      return e;
    })({});
    """

    func testSearchDecodesEntitiesAndSkipsRowsWithoutId() async throws {
        let rows = try await source(bundle).search(query: "x", page: 1)
        XCTAssertEqual(rows.map(\.id), ["m1"])
        XCTAssertEqual(rows.first?.title, "A & B x")
        XCTAssertEqual(rows.first?.coverURL, "https://cdn.example/c.jpg")
    }

    func testDetailsDropInsecureCover() async throws {
        let details = try await source(bundle).details(for: MangaSummary(id: "m1", title: "M"))
        XCTAssertEqual(details.title, "T m1")
        XCTAssertNil(details.coverURL)
    }

    func testChaptersCarrySeriesIdAndPagesGetInterceptorHeaders() async throws {
        let fake = try source(bundle)
        let chapters = try await fake.chapters(for: MangaSummary(id: "m1", title: "M"))
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters.first?.name, "Chapter 3")
        let pages = try await fake.pages(for: chapters[0])
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages.first?.headers?["referer"], "https://site.example/")
    }

    func testScriptCannotReachLocalAddresses() async throws {
        let script = """
        var source = {Fake: {async getSearchResults() {
          const [r] = await Application.scheduleRequest({url: "https://127.0.0.1/x", method: "GET"});
          return {items: []};
        }}};
        """
        do { _ = try await source(script).search(query: "x", page: 1); XCTFail("Expected a blocked request") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Blocked")) }
    }

    func testExtensionErrorsSurface() async throws {
        let script = "var source = {Fake: {async getSearchResults() { throw new Error('boom'); }}};"
        do { _ = try await source(script).search(query: "x", page: 1); XCTFail("Expected an error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("boom")) }
    }

    func testAnyPublicHTTPSPolicy() {
        let policy = SourceAccessPolicy(hosts: [], anyPublicHTTPS: true)
        XCTAssertTrue(policy.allows(URL(string: "https://mangapill.com/a")!))
        XCTAssertFalse(policy.allows(URL(string: "http://mangapill.com/a")!))
        XCTAssertFalse(policy.allows(URL(string: "https://192.168.1.5/a")!))
        XCTAssertFalse(policy.allows(URL(string: "https://localhost/a")!))
        XCTAssertFalse(policy.allows(URL(string: "https://user:pw@mangapill.com/a")!))
    }

    func testRepositoryAddressNormalising() {
        let base = "https://inkdex.github.io/general-extensions/0.9/stable"
        XCTAssertEqual(PaperbackStore.normalizedBase(base + "/"), base)
        XCTAssertEqual(PaperbackStore.normalizedBase(base + "/versioning.json"), base)
        XCTAssertNil(PaperbackStore.normalizedBase("http://example.com/x"))
        XCTAssertNil(PaperbackStore.normalizedBase("https://192.168.0.2/x"))
        XCTAssertNil(PaperbackStore.normalizedBase("https://example.com/x?token=1"))
    }

    func testIndexParsingDropsAdultAndBadEntries() {
        let json = """
        {"repository":{"name":"R"},"sources":[
          {"id":"Good","name":"Good","version":"1","contentRating":"SAFE","language":"en"},
          {"id":"Mature","name":"Mature","version":"2","contentRating":"MATURE"},
          {"id":"Adult","name":"Adult","version":"1","contentRating":"ADULT"},
          {"id":"../evil","name":"Evil","version":"1"},
          {"name":"No id"}
        ]}
        """
        let rows = PaperbackStore.parseIndex(Data(json.utf8), base: "https://example.com/r")
        XCTAssertEqual(rows.map(\.id), ["Good", "Mature"])
        XCTAssertEqual(rows.first?.repository, "https://example.com/r")
    }
}
#endif
