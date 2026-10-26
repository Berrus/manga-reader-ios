import XCTest
import SwiftData
import UIKit
@testable import MangaReader

private struct DownloadFixtureSource: Source {
    let id = "fixture"
    let name = "Fixture"
    let count: Int
    var accessPolicy: SourceAccessPolicy { SourceAccessPolicy(hosts: ["example.com"]) }
    func search(query: String, page: Int) async throws -> [MangaSummary] { [] }
    func details(for manga: MangaSummary) async throws -> MangaDetails { MangaDetails() }
    func chapters(for manga: MangaSummary) async throws -> [ChapterSummary] { [] }
    func pages(for chapter: ChapterSummary) async throws -> [PageSource] {
        (0..<count).map { PageSource(url: "https://example.com/\($0).png") }
    }
}

private actor DownloadGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<Data, Never>?
    func fetch() async -> Data {
        await withCheckedContinuation { continuation in
            started = true
            self.continuation = continuation
        }
    }
    func release(_ data: Data) { continuation?.resume(returning: data); continuation = nil }
}

@MainActor
final class DownloadLifecycleTests: XCTestCase {
    private var retainedStores: [ModelContainer] = []
    private func context() throws -> ModelContext {
        let schema = Schema([Manga.self, Chapter.self, TrackLink.self, Category.self])
        let store = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        retainedStores.append(store)
        return store.mainContext
    }
    private func chapter(in context: ModelContext) -> Chapter {
        let manga = Manga(title: "Book", coverData: nil)
        manga.sourceID = "fixture"; manga.remoteID = UUID().uuidString
        context.insert(manga)
        let chapter = Chapter(name: "Chapter", number: 1, fileName: "", pageCount: 0)
        chapter.remoteID = UUID().uuidString
        context.insert(chapter); chapter.manga = manga
        return chapter
    }
    private func queueURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }
    private func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { _ in
            UIColor.blue.setFill(); UIBezierPath(rect: CGRect(x: 0, y: 0, width: 8, height: 8)).fill()
        }
    }
    private func waitForStop(_ manager: DownloadManager) async throws {
        for _ in 0..<200 {
            if !manager.isPumping { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Download queue did not stop")
    }
    private func waitForStart(_ gate: DownloadGate) async throws {
        for _ in 0..<200 {
            if await gate.started { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Download did not start")
    }

    func testQueuedWorkSurvivesManagerRecreation() throws {
        let context = try self.context()
        let chapter = self.chapter(in: context)
        let url = queueURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let manager = DownloadManager(queueURL: url, canDownload: { false })
        manager.enqueue([chapter])
        let restored = DownloadManager(queueURL: url, canDownload: { false })
        restored.resume(context: context)
        XCTAssertEqual(restored.jobs.map(\.chapterID), [chapter.id])
        XCTAssertFalse(restored.jobs[0].isActive)
    }

    func testWiFiLossStopsBeforePublishingAndResumeRetriesChapter() async throws {
        let context = try self.context()
        let chapter = self.chapter(in: context)
        let url = queueURL()
        let data = png()
        var allowed = true
        var requests = 0
        let manager = DownloadManager(queueURL: url, canDownload: { allowed },
            resolve: { _ in DownloadFixtureSource(count: 2) },
            fetchPage: { _, _ in requests += 1; if requests == 1 { allowed = false }; return data })
        defer { chapter.removeFiles(); try? FileManager.default.removeItem(at: url) }
        manager.enqueue([chapter])
        try await waitForStop(manager)
        XCTAssertEqual(requests, 1)
        XCTAssertFalse(chapter.isDownloaded)
        XCTAssertEqual(manager.jobs.count, 1)
        allowed = true
        manager.resume(context: context)
        try await waitForStop(manager)
        XCTAssertTrue(chapter.isDownloaded)
        XCTAssertEqual(chapter.pageCount, 2)
        XCTAssertEqual(requests, 3)
        XCTAssertTrue(manager.jobs.isEmpty)
    }

    func testCancelDuringFinalPageCannotPublishDownload() async throws {
        let context = try self.context()
        let chapter = self.chapter(in: context)
        let url = queueURL()
        let gate = DownloadGate()
        let manager = DownloadManager(queueURL: url, canDownload: { true },
            resolve: { _ in DownloadFixtureSource(count: 1) }, fetchPage: { _, _ in await gate.fetch() })
        defer { chapter.removeFiles(); try? FileManager.default.removeItem(at: url) }
        manager.enqueue([chapter])
        try await waitForStart(gate)
        manager.cancel(chapterID: chapter.id)
        await gate.release(png()) // Deliberately emulate a transport returning after cancellation.
        try await waitForStop(manager)
        XCTAssertFalse(chapter.isDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: chapter.downloadDirectory.path))
        XCTAssertTrue(manager.jobs.isEmpty)
    }

    func testDeleteWaitsForActiveDownloadToAcknowledgeCancellation() async throws {
        let context = try self.context()
        let chapter = self.chapter(in: context)
        let url = queueURL()
        let gate = DownloadGate()
        let manager = DownloadManager(queueURL: url, canDownload: { true },
            resolve: { _ in DownloadFixtureSource(count: 1) }, fetchPage: { _, _ in await gate.fetch() })
        defer { try? FileManager.default.removeItem(at: url) }
        manager.enqueue([chapter])
        try await waitForStart(gate)
        manager.cancel(chapterID: chapter.id)
        let cancelling = Task { await manager.cancelAndWait([chapter.id]) }
        await Task.yield()
        await gate.release(png())
        await cancelling.value
        context.delete(chapter)
        try context.save()
        try await waitForStop(manager)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Chapter>()), 0)
        XCTAssertTrue(manager.jobs.isEmpty)
    }

    func testPauseKeepsWorkForRelaunch() async throws {
        let context = try self.context()
        let chapter = self.chapter(in: context)
        let url = queueURL()
        let gate = DownloadGate()
        let manager = DownloadManager(queueURL: url, canDownload: { true },
            resolve: { _ in DownloadFixtureSource(count: 1) }, fetchPage: { _, _ in await gate.fetch() })
        defer { chapter.removeFiles(); try? FileManager.default.removeItem(at: url) }
        manager.enqueue([chapter])
        try await waitForStart(gate)
        manager.pause()
        await gate.release(png())
        try await waitForStop(manager)
        let restored = DownloadManager(queueURL: url, canDownload: { false })
        restored.resume(context: context)
        XCTAssertEqual(restored.jobs.map(\.chapterID), [chapter.id])
        XCTAssertFalse(chapter.isDownloaded)
    }
}
