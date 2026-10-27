import XCTest
@testable import MangaReader

final class MangaDexRecommendationTests: XCTestCase {
    private func item() throws -> MangaDexSource.MangaItem {
        let json = Data("""
        {"id":"self","attributes":{"title":{"en":"Me"},"tags":[
          {"id":"t-action","attributes":{"group":"genre"}},
          {"id":"t-gore","attributes":{"group":"content"}},
          {"id":"t-school","attributes":{"group":"theme"}},
          {"id":"t-4koma","attributes":{"group":"format"}},
          {"id":"t-drama","attributes":{"group":"genre"}},
          {"id":"t-extra","attributes":{"group":"genre"}}]},
         "relationships":[{"id":"r1","type":"manga"},{"id":"a1","type":"author"},{"type":"manga"},{"id":"r2","type":"manga"}]}
        """.utf8)
        return try JSONDecoder().decode(MangaDexSource.MangaItem.self, from: json)
    }

    func testOnlyGenreAndThemeTagsAreUsedAndCappedAtThree() throws {
        XCTAssertEqual(MangaDexSource.similarTagIDs(of: try item()), ["t-action", "t-school", "t-drama"])
    }

    func testRelatedIdsAreMangaRelationshipsWithAnId() throws {
        XCTAssertEqual(MangaDexSource.relatedIDs(of: try item()), ["r1", "r2"])
    }

    func testSimilarQueryKeepsSafeRatingsAndRequiresAllTags() {
        let items = MangaDexSource.similarQuery(tagIDs: ["a", "b"])
        func values(_ name: String) -> [String] { items.filter { $0.name == name }.compactMap(\.value) }
        XCTAssertEqual(values("includedTags[]"), ["a", "b"])
        XCTAssertEqual(values("includedTagsMode"), ["AND"])
        XCTAssertEqual(Set(values("contentRating[]")), ["safe", "suggestive"])
        XCTAssertFalse(values("contentRating[]").contains("erotica"))
    }

    func testDedupeDropsTheViewedTitleAndRepeats() throws {
        func make(_ id: String) throws -> MangaDexSource.MangaItem {
            try JSONDecoder().decode(MangaDexSource.MangaItem.self,
                from: Data(#"{"id":"\#(id)","attributes":{"title":{"en":"T"}},"relationships":[]}"#.utf8))
        }
        let result = MangaDexSource.dedupe([try make("a"), try make("self"), try make("a"), try make("b")], excluding: "self")
        XCTAssertEqual(result.map(\.id), ["a", "b"])
    }

    func testOtherSourcesOfferNoRecommendationsByDefault() async throws {
        let source = KomgaSource(config: ServerConfig(kind: .komga, name: "n", url: "http://192.168.1.2:25600", username: "u"), password: "p")
        let result = try await source?.related(to: MangaSummary(id: "1", title: "x", coverURL: nil))
        XCTAssertEqual(result?.count, 0)
    }
}
