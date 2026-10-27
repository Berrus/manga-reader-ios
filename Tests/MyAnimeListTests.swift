import XCTest
@testable import MangaReader

final class MyAnimeListTests: XCTestCase {
    func testAuthorizeURLUsesPlainPKCEWithMatchingChallenge() throws {
        let url = MyAnimeListAuth.authorizeURL(clientID: "client", verifier: "verifier123", state: "state456")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["code_challenge"], "verifier123")
        XCTAssertEqual(items["code_challenge_method"], "plain")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["client_id"], "client")
        XCTAssertEqual(items["state"], "state456")
        XCTAssertEqual(items["redirect_uri"], "folioreader://mal")
    }

    func testRandomStringIsAValidPKCEVerifier() {
        let value = MyAnimeListAuth.randomString()
        XCTAssertEqual(value.count, 43)
        XCTAssertNil(value.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertNotEqual(value, MyAnimeListAuth.randomString())
    }

    func testCodeIsReadOnlyWhenTheStateMatches() throws {
        let good = try XCTUnwrap(URL(string: "folioreader://mal?code=abc123&state=xyz"))
        XCTAssertEqual(try MyAnimeListAuth.code(from: good, expectedState: "xyz"), "abc123")
        XCTAssertThrowsError(try MyAnimeListAuth.code(from: good, expectedState: "other"))
        let denied = try XCTUnwrap(URL(string: "folioreader://mal?error=access_denied&state=xyz"))
        XCTAssertNil(try MyAnimeListAuth.code(from: denied, expectedState: "xyz"))
    }

    func testFormBodyEncodesReservedCharacters() {
        let body = String(decoding: MyAnimeListAuth.formBody(["b": "a b&c=d", "a": "é"]), as: UTF8.self)
        XCTAssertEqual(body, "a=%C3%A9&b=a%20b%26c%3Dd")
    }

    func testSearchResultsAndMissingChapterCounts() throws {
        let json = Data("""
        {"data":[{"node":{"id":1,"title":"One Piece","num_chapters":0,"main_picture":{"medium":"https://cdn.example/1.jpg"}}},
                 {"node":{"id":2,"title":"Done","num_chapters":12}}]}
        """.utf8)
        let results = try MyAnimeListTracker.results(from: json)
        XCTAssertEqual(results.map(\.remoteId), [1, 2])
        XCTAssertNil(results[0].totalChapters, "0 means the series is ongoing/unknown")
        XCTAssertEqual(results[1].totalChapters, 12)
        XCTAssertEqual(results[0].coverURL?.absoluteString, "https://cdn.example/1.jpg")
    }

    func testEntryParsingAndNotOnListDefault() throws {
        let onList = Data(#"{"id":5,"my_list_status":{"status":"on_hold","score":8,"num_chapters_read":42}}"#.utf8)
        let entry = try MyAnimeListTracker.entry(from: onList, remoteId: 5)
        XCTAssertEqual(entry.chaptersRead, 42)
        XCTAssertEqual(entry.status, .onHold)
        XCTAssertEqual(entry.score, 8)
        let notOnList = try MyAnimeListTracker.entry(from: Data(#"{"id":6}"#.utf8), remoteId: 6)
        XCTAssertEqual(notOnList.chaptersRead, 0)
        XCTAssertEqual(notOnList.status, .planning)
        XCTAssertNil(try MyAnimeListTracker.entry(from: Data(#"{"id":6,"my_list_status":{"score":0}}"#.utf8), remoteId: 6).score)
    }

    func testStatusMappingRoundTrips() {
        for status in ReadStatus.allCases {
            XCTAssertEqual(MyAnimeListTracker.status(from: MyAnimeListTracker.malStatus(status)), status)
        }
        XCTAssertEqual(MyAnimeListTracker.status(from: nil), .planning)
    }
}
