import XCTest
import SwiftData
@testable import MangaReader

private final class FakeTracker: Tracker, @unchecked Sendable {
    let id = "fake"
    let name = "Fake"
    var remote: TrackEntry
    var pushed: [TrackEntry] = []
    init(remote: TrackEntry) { self.remote = remote }
    func search(_ title: String) async throws -> [TrackSearchResult] { [] }
    func fetch(remoteId: Int) async throws -> TrackEntry { remote }
    func push(_ entry: TrackEntry) async throws { pushed.append(entry) }
}

@MainActor
final class TrackerSyncTests: XCTestCase {
    private var retainedStores: [ModelContainer] = []
    private func makeManga(read: Set<Double>, numbers: [Double]) throws -> (Manga, TrackLink, ModelContext) {
        let schema = Schema([Manga.self, Chapter.self, TrackLink.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        retainedStores.append(container)
        let context = container.mainContext
        let manga = Manga(title: "Series", coverData: nil)
        context.insert(manga)
        for number in numbers {
            let chapter = Chapter(name: "Ch \(number)", number: number, fileName: "\(number).cbz", pageCount: 5)
            context.insert(chapter)
            chapter.manga = manga
            chapter.isRead = read.contains(number)
        }
        let link = TrackLink(mangaID: manga.id, trackerID: "fake", remoteId: 1, remoteTitle: "Series")
        context.insert(link)
        return (manga, link, context)
    }

    func testRemoteAheadMarksLocalChaptersRead() async throws {
        let (manga, link, _) = try makeManga(read: [1], numbers: [1, 2, 3, 4])
        let tracker = FakeTracker(remote: TrackEntry(remoteId: 1, chaptersRead: 3, status: .reading))
        let outcome = try await TrackerSync().reconcile(manga: manga, link: link, tracker: tracker)
        XCTAssertEqual(outcome, .pulled(3))
        XCTAssertEqual(manga.sortedChapters.map(\.isRead), [true, true, true, false])
        XCTAssertTrue(tracker.pushed.isEmpty)
    }

    func testLocalAheadPushesAndKeepsRemoteFields() async throws {
        let (manga, link, _) = try makeManga(read: [1, 2, 3], numbers: [1, 2, 3, 4])
        let tracker = FakeTracker(remote: TrackEntry(remoteId: 1, chaptersRead: 1, status: .planning, score: 8))
        let outcome = try await TrackerSync().reconcile(manga: manga, link: link, tracker: tracker)
        XCTAssertEqual(outcome, .pushed(3))
        XCTAssertEqual(tracker.pushed.first?.chaptersRead, 3)
        XCTAssertEqual(tracker.pushed.first?.status, .reading)
        XCTAssertEqual(tracker.pushed.first?.score, 8)
        XCTAssertNotNil(link.lastSyncedAt)
    }

    func testEqualProgressChangesNothing() async throws {
        let (manga, link, _) = try makeManga(read: [1, 2], numbers: [1, 2, 3])
        let tracker = FakeTracker(remote: TrackEntry(remoteId: 1, chaptersRead: 2, status: .reading))
        let outcome = try await TrackerSync().reconcile(manga: manga, link: link, tracker: tracker)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertTrue(tracker.pushed.isEmpty)
    }

    func testUnnumberedChaptersAreNeverMarkedReadFromRemote() async throws {
        let (manga, link, _) = try makeManga(read: [], numbers: [0, 0, 1])
        let tracker = FakeTracker(remote: TrackEntry(remoteId: 1, chaptersRead: 40, status: .reading))
        _ = try await TrackerSync().reconcile(manga: manga, link: link, tracker: tracker)
        XCTAssertEqual(manga.chapters.filter { $0.number == 0 }.filter(\.isRead).count, 0)
    }

    func testCompletedStatusIsNotDowngradedOnPush() async throws {
        let (manga, link, _) = try makeManga(read: [1, 2], numbers: [1, 2])
        let tracker = FakeTracker(remote: TrackEntry(remoteId: 1, chaptersRead: 1, status: .completed))
        _ = try await TrackerSync().reconcile(manga: manga, link: link, tracker: tracker)
        XCTAssertEqual(tracker.pushed.first?.status, .completed)
    }
}

final class AniListMappingTests: XCTestCase {
    func testTokenIsReadFromRedirectFragment() {
        let url = URL(string: "folioreader://anilist#access_token=abc.def&token_type=Bearer&expires_in=31536000")!
        XCTAssertEqual(AniListAuth.token(from: url), "abc.def")
        XCTAssertNil(AniListAuth.token(from: URL(string: "folioreader://anilist?error=access_denied")!))
    }

    func testStatusMappingRoundTrips() {
        for status in ReadStatus.allCases {
            XCTAssertEqual(AniListTracker.status(from: AniListTracker.anilistStatus(status)), status)
        }
        XCTAssertEqual(AniListTracker.status(from: "REPEATING"), .reading)
        XCTAssertEqual(AniListTracker.status(from: nil), .planning)
    }
}
