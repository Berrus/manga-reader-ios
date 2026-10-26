import XCTest
@testable import MangaReader

private actor FeedProbe {
    var active = 0
    var peak = 0
    func begin() { active += 1; peak = max(peak, active) }
    func end() { active -= 1 }
}
private struct FeedTestSource: Source {
    let id = "feed-test"
    let name = "Feed test"
    let probe: FeedProbe
    func search(query: String, page: Int) async throws -> [MangaSummary] {
        await probe.begin()
        do { try await Task.sleep(nanoseconds: 30_000_000) }
        catch { await probe.end(); throw error }
        await probe.end()
        return [MangaSummary(id: "0", title: "Duplicate")] +
            (0..<30).map { MangaSummary(id: "\($0)", title: "Title \($0)") }
    }
    func details(for manga: MangaSummary) async throws -> MangaDetails { MangaDetails() }
    func chapters(for manga: MangaSummary) async throws -> [ChapterSummary] { [] }
    func pages(for chapter: ChapterSummary) async throws -> [PageSource] { [] }
}
@MainActor
final class FeedTests: XCTestCase {
    private func entries(_ count: Int) -> [SavedSearchStore.Entry] {
        (0..<count).map { .init(id: UUID(), sourceID: "feed-test", query: "Search \($0)") }
    }
    func testFeedBoundsQueriesConcurrencyAndDeduplicatesResults() async {
        let probe = FeedProbe()
        let vm = FeedViewModel(resolve: { _ in FeedTestSource(probe: probe) })
        await vm.load(entries(12))
        XCTAssertEqual(vm.sections.count, 8)
        XCTAssertEqual(vm.sections.map(\.query), (0..<8).map { "Search \($0)" })
        XCTAssertTrue(vm.sections.allSatisfy { $0.results.count == 20 && !$0.isLoading && $0.error == nil })
        XCTAssertTrue(vm.sections.allSatisfy { Set($0.results.map(\.id)).count == 20 })
        let peak = await probe.peak
        XCTAssertLessThanOrEqual(peak, 3)
        XCTAssertFalse(vm.isLoading)
    }
    func testUnavailableFeedSourceShowsRecoverableIssue() async {
        let vm = FeedViewModel(resolve: { _ in nil })
        await vm.load(entries(1))
        XCTAssertEqual(vm.sections[0].error, "Source unavailable. Check Settings.")
        XCTAssertFalse(vm.sections[0].isLoading)
    }
    func testCancelledFeedDoesNotPublishStaleResults() async throws {
        let probe = FeedProbe()
        let vm = FeedViewModel(resolve: { _ in FeedTestSource(probe: probe) })
        let task = Task { await vm.load(entries(3)) }
        for _ in 0..<100 {
            if await probe.active > 0 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        task.cancel()
        await task.value
        XCTAssertTrue(vm.sections.allSatisfy { $0.results.isEmpty })
        XCTAssertFalse(vm.isLoading)
    }
}
