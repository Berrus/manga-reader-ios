import XCTest
@testable import MangaReader

final class SuwayomiTests: XCTestCase {
    private func config(_ url: String, user: String = "", kind: ServerConfig.Kind = .suwayomi) -> ServerConfig {
        ServerConfig(kind: kind, name: "Home", url: url, username: user)
    }

    // MARK: Client setup

    func testLocalHTTPServersAreAcceptedAndPublicHTTPIsNot() {
        XCTAssertNotNil(SuwayomiClient(config: config("http://192.168.1.5:4567"), password: ""))
        XCTAssertNotNil(SuwayomiClient(config: config("https://suwayomi.example.com"), password: ""))
        XCTAssertNil(SuwayomiClient(config: config("http://suwayomi.example.com"), password: ""))
        XCTAssertNil(SuwayomiClient(config: config("ftp://192.168.1.5"), password: ""))
        XCTAssertNil(SuwayomiClient(config: config("https://user:pw@suwayomi.example.com"), password: ""))
    }

    func testAuthorizationHeaderOnlyWhenCredentialsAreGiven() throws {
        let open = try XCTUnwrap(SuwayomiClient(config: config("http://192.168.1.5:4567"), password: ""))
        XCTAssertNil(open.authorization)
        XCTAssertTrue(open.imageHeaders.isEmpty)
        let secured = try XCTUnwrap(SuwayomiClient(config: config("http://192.168.1.5:4567", user: "me"), password: "pw"))
        XCTAssertEqual(secured.authorization, "Basic " + Data("me:pw".utf8).base64EncodedString())
        XCTAssertEqual(secured.imageHeaders["Authorization"], secured.authorization)
    }

    func testTrailingSlashIsIgnored() throws {
        let client = try XCTUnwrap(SuwayomiClient(config: config("http://192.168.1.5:4567///"), password: ""))
        XCTAssertEqual(client.base.absoluteString, "http://192.168.1.5:4567")
    }

    // MARK: Requests and responses

    func testRequestBodyCarriesQueryAndVariables() throws {
        let data = try SuwayomiClient.body(query: "{ aboutServer { name } }", variables: ["input": ["page": 1]])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["query"] as? String, "{ aboutServer { name } }")
        XCTAssertEqual((json["variables"] as? [String: Any])?["input"] as? [String: Int], ["page": 1])
    }

    func testGraphQLErrorsBecomeReadableErrors() {
        let json = Data(#"{"data":null,"errors":[{"message":"Source not found"}]}"#.utf8)
        XCTAssertThrowsError(try SuwayomiClient.decode(json) as SuwayomiClient.AboutData) { error in
            guard case SuwayomiError.server(let message) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(message, "Source not found")
        }
    }

    func testNonSuwayomiResponsesAreRecognised() throws {
        XCTAssertThrowsError(try SuwayomiClient.decode(Data("<html>nginx</html>".utf8)) as SuwayomiClient.AboutData) { error in
            guard case SuwayomiError.notSuwayomi = error else { return XCTFail("\(error)") }
        }
        let empty: SuwayomiClient.AboutData = try SuwayomiClient.decode(Data(#"{"data":{"aboutServer":null}}"#.utf8))
        XCTAssertNil(empty.aboutServer)
    }

    func testSourcesDecodeNumericOrStringIdsAndHideAdultSources() throws {
        let json = Data("""
        {"data":{"sources":{"nodes":[
          {"id":"2499283573021220255","name":"Zeta","lang":"en","displayName":"Zeta (EN)","isNsfw":false},
          {"id":1234,"name":"Alpha","lang":"ja","displayName":"Alpha (JA)","isNsfw":false},
          {"id":"9","name":"Adult","lang":"en","displayName":"Adult","isNsfw":true}]}}}
        """.utf8)
        let data: SuwayomiClient.SourcesData = try SuwayomiClient.decode(json)
        let visible = SuwayomiClient.visibleSources(data.sources.nodes)
        XCTAssertEqual(visible.map(\.id), ["1234", "2499283573021220255"])
        XCTAssertEqual(visible.map(\.displayName), ["Alpha (JA)", "Zeta (EN)"])
    }

    func testSearchResultsDecode() throws {
        let json = Data("""
        {"data":{"fetchSourceManga":{"hasNextPage":true,"mangas":[
          {"id":7,"title":"One","thumbnailUrl":"/api/v1/manga/7/thumbnail"},
          {"id":8,"title":"Two","thumbnailUrl":null}]}}}
        """.utf8)
        let data: SuwayomiClient.SourceMangaData = try SuwayomiClient.decode(json)
        XCTAssertEqual(data.fetchSourceManga.mangas.map(\.id), [7, 8])
        XCTAssertNil(data.fetchSourceManga.mangas[1].thumbnailUrl)
    }

    func testPagesDecode() throws {
        let json = Data(#"{"data":{"fetchChapterPages":{"pages":["/api/v1/manga/1/chapter/2/page/0","/api/v1/manga/1/chapter/2/page/1"]}}}"#.utf8)
        let data: SuwayomiClient.PagesData = try SuwayomiClient.decode(json)
        XCTAssertEqual(data.fetchChapterPages.pages.count, 2)
    }

    // MARK: URLs

    func testRelativePathsKeepAnyServerSubPath() throws {
        let plain = try XCTUnwrap(URL(string: "http://192.168.1.5:4567"))
        XCTAssertEqual(SuwayomiClient.absoluteURL("/api/v1/manga/1/thumbnail", base: plain)?.absoluteString,
                       "http://192.168.1.5:4567/api/v1/manga/1/thumbnail")
        let mounted = try XCTUnwrap(URL(string: "https://example.com/suwayomi"))
        XCTAssertEqual(SuwayomiClient.absoluteURL("/api/v1/manga/1/thumbnail", base: mounted)?.absoluteString,
                       "https://example.com/suwayomi/api/v1/manga/1/thumbnail")
        XCTAssertEqual(SuwayomiClient.absoluteURL("api/v1/x", base: plain)?.absoluteString,
                       "http://192.168.1.5:4567/api/v1/x")
        XCTAssertEqual(SuwayomiClient.absoluteURL("https://cdn.example.org/a.jpg", base: plain)?.absoluteString,
                       "https://cdn.example.org/a.jpg")
    }

    // MARK: Chapters

    func testChaptersAreOldestFirstAndUnnumberedOnesKeepSourceOrder() {
        let nodes = [
            SuwayomiClient.ChapterNode(id: 1, name: "Ch 3", chapterNumber: 3, sourceOrder: 1),
            SuwayomiClient.ChapterNode(id: 2, name: "Ch 1", chapterNumber: 1, sourceOrder: 3),
            SuwayomiClient.ChapterNode(id: 3, name: "Special", chapterNumber: -1, sourceOrder: 2),
            SuwayomiClient.ChapterNode(id: 4, name: "Ch 2", chapterNumber: 2, sourceOrder: 2)
        ]
        let result = SuwayomiSource.chapterList(from: nodes)
        XCTAssertEqual(result.first?.name, "Ch 1")
        XCTAssertEqual(result.last?.name, "Ch 3")
        XCTAssertNil(result.first { $0.name == "Special" }?.number)
        XCTAssertEqual(result.first { $0.name == "Ch 2" }?.number, 2)
    }

    // MARK: Identifiers

    func testSourceIdsRoundTrip() throws {
        let server = UUID()
        let id = SuwayomiSource.makeID(server: server, source: "2499283573021220255")
        let parsed = try XCTUnwrap(SuwayomiSource.parseID(id))
        XCTAssertEqual(parsed.server, server)
        XCTAssertEqual(parsed.source, "2499283573021220255")
    }

    func testMalformedSourceIdsAreRejected() {
        XCTAssertNil(SuwayomiSource.parseID("komga.\(UUID().uuidString)"))
        XCTAssertNil(SuwayomiSource.parseID("suwayomi.not-a-uuid.123"))
        XCTAssertNil(SuwayomiSource.parseID("suwayomi.\(UUID().uuidString)"))
        XCTAssertNil(SuwayomiSource.parseID("suwayomi.\(UUID().uuidString)."))
    }

    func testExistingKomgaServerFilesStillDecode() throws {
        let json = Data(#"[{"id":"\#(UUID().uuidString)","kind":"komga","name":"Old","url":"http://nas:25600","username":"me"}]"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode([ServerConfig].self, from: json).first?.kind, .komga)
    }
}
