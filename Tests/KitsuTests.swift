import XCTest
@testable import MangaReader

final class KitsuTests: XCTestCase {
    func testUserIdIsReadFromTheSelfFilter() {
        XCTAssertEqual(KitsuAuth.userID(from: Data(#"{"data":[{"id":"42","type":"users"}]}"#.utf8)), "42")
        XCTAssertNil(KitsuAuth.userID(from: Data(#"{"data":[]}"#.utf8)))
    }

    func testSearchResultsSkipNonNumericIdsAndUnknownChapterCounts() throws {
        let json = Data("""
        {"data":[{"id":"7","attributes":{"canonicalTitle":"Berserk","chapterCount":null,"posterImage":{"small":"https://x/a.jpg"}}},
                 {"id":"oops","attributes":{"canonicalTitle":"Bad"}},
                 {"id":"9","attributes":{"canonicalTitle":"Done","chapterCount":30}}]}
        """.utf8)
        let results = try KitsuTracker.results(from: json)
        XCTAssertEqual(results.map(\.remoteId), [7, 9])
        XCTAssertNil(results[0].totalChapters)
        XCTAssertEqual(results[1].totalChapters, 30)
    }

    func testEntryParsingConvertsRatingAndStatus() throws {
        let json = Data(#"{"data":[{"id":"555","attributes":{"status":"on_hold","progress":12,"ratingTwenty":16}}]}"#.utf8)
        let (entryID, entry) = try KitsuTracker.entry(from: json, remoteId: 7)
        XCTAssertEqual(entryID, "555")
        XCTAssertEqual(entry.chaptersRead, 12)
        XCTAssertEqual(entry.status, .onHold)
        XCTAssertEqual(entry.score, 8)
    }

    func testNotOnTheListYetMeansNoEntryIdAndPlanned() throws {
        let (entryID, entry) = try KitsuTracker.entry(from: Data(#"{"data":[]}"#.utf8), remoteId: 7)
        XCTAssertNil(entryID)
        XCTAssertEqual(entry.status, .planning)
        XCTAssertEqual(entry.chaptersRead, 0)
    }

    func testStatusMappingRoundTrips() {
        for status in ReadStatus.allCases {
            XCTAssertEqual(KitsuTracker.status(from: KitsuTracker.kitsuStatus(status)), status)
        }
    }

    func testCreateAndUpdateBodies() throws {
        let entry = TrackEntry(remoteId: 7, chaptersRead: 12.7, status: .reading, score: 8)
        let create = try XCTUnwrap(JSONSerialization.jsonObject(with: KitsuTracker.createBody(userID: "42", entry: entry)) as? [String: Any])
        let data = try XCTUnwrap(create["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
        XCTAssertEqual(attributes["progress"] as? Int, 12)
        XCTAssertEqual(attributes["status"] as? String, "current")
        XCTAssertEqual(attributes["ratingTwenty"] as? Int, 16)
        let relationships = try XCTUnwrap(data["relationships"] as? [String: Any])
        XCTAssertEqual(((relationships["media"] as? [String: Any])?["data"] as? [String: String])?["id"], "7")

        let update = try XCTUnwrap(JSONSerialization.jsonObject(with: KitsuTracker.updateBody(entryID: "555", entry: entry)) as? [String: Any])
        XCTAssertEqual((update["data"] as? [String: Any])?["id"] as? String, "555")
    }

    func testScoreIsClampedToKitsusRange() throws {
        let low = TrackEntry(remoteId: 1, chaptersRead: 1, status: .reading, score: 0.2)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: KitsuTracker.updateBody(entryID: "1", entry: low)) as? [String: Any])
        let rating = ((json["data"] as? [String: Any])?["attributes"] as? [String: Any])?["ratingTwenty"] as? Int
        XCTAssertEqual(rating, 2)
    }
}
