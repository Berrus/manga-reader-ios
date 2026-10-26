import XCTest
import SwiftData
@testable import MangaReader

@MainActor
final class AutoDownloadPolicyTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Manga.self, Chapter.self, TrackLink.self, Category.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ]).mainContext
    }

    /// A remote series with chapters 1...count; the first `read` are read and `downloaded` are on disk.
    private func series(_ context: ModelContext, count: Int = 8, read: Int = 0,
                        downloaded: Set<Int> = [], remote: Bool = true) -> Manga {
        let manga = Manga(title: "Series", coverData: nil)
        if remote { manga.sourceID = "mangadex"; manga.remoteID = "abc" }
        context.insert(manga)
        for number in 1...count {
            let chapter = Chapter(name: "Ch \(number)", number: Double(number), fileName: "", pageCount: 0)
            if remote { chapter.remoteID = "c\(number)" }
            context.insert(chapter)
            chapter.manga = manga
            chapter.isRead = number <= read
            chapter.isDownloaded = downloaded.contains(number)
        }
        return manga
    }

    private func numbers(_ chapters: [Chapter]) -> [Int] { chapters.map { Int($0.number) } }

    func testOffDownloadsNothing() throws {
        let manga = series(try makeContext(), read: 2)
        XCTAssertTrue(AutoDownloadPolicy.candidates(for: manga, scope: .off, ahead: 3, newChapters: []).isEmpty)
    }

    func testReadingScopeNeedsAStartedSeries() throws {
        let context = try makeContext()
        let fresh = series(context)
        XCTAssertTrue(AutoDownloadPolicy.candidates(for: fresh, scope: .reading, ahead: 2, newChapters: []).isEmpty)
        let started = series(context, read: 2)
        XCTAssertEqual(numbers(AutoDownloadPolicy.candidates(for: started, scope: .reading, ahead: 2, newChapters: [])), [3, 4])
    }

    func testSelectedScopeRequiresTheSeriesToBeSwitchedOn() throws {
        let manga = series(try makeContext(), read: 1)
        XCTAssertTrue(AutoDownloadPolicy.candidates(for: manga, scope: .selected, ahead: 2, newChapters: []).isEmpty)
        manga.autoDownload = true
        XCTAssertEqual(numbers(AutoDownloadPolicy.candidates(for: manga, scope: .selected, ahead: 2, newChapters: [])), [2, 3])
    }

    func testAlreadyDownloadedChaptersCountTowardsTheAheadLimit() throws {
        let manga = series(try makeContext(), read: 1, downloaded: [2])
        manga.autoDownload = true
        XCTAssertEqual(numbers(AutoDownloadPolicy.candidates(for: manga, scope: .selected, ahead: 2, newChapters: [])), [3])
    }

    func testUpdatedScopeTakesNewestNewChaptersForAnySeries() throws {
        let manga = series(try makeContext(), count: 7)
        let new = manga.sortedChapters.filter { $0.number >= 5 }
        XCTAssertEqual(numbers(AutoDownloadPolicy.candidates(for: manga, scope: .updated, ahead: 2, newChapters: new)), [6, 7])
    }

    func testImportedSeriesAreNeverQueued() throws {
        let manga = series(try makeContext(), read: 1, remote: false)
        manga.autoDownload = true
        XCTAssertTrue(AutoDownloadPolicy.candidates(for: manga, scope: .selected, ahead: 3, newChapters: []).isEmpty)
    }

    func testRemovingFilesOfAnImportedChapterWithoutFileNeverTouchesTheLibraryFolder() throws {
        let books = LibraryImporter.booksDirectory
        let marker = books.appendingPathComponent("keep-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: marker)
        defer { try? FileManager.default.removeItem(at: marker) }
        let chapter = Chapter(name: "Empty", number: 1, fileName: "", pageCount: 0)
        chapter.removeFiles()
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testDirectoryPagesAreReadInNaturalOrder() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["0010.jpg", "0002.jpg", "0001.jpg"] {
            try Data(name.utf8).write(to: dir.appendingPathComponent(name))
        }
        let pages = try DirectoryPages(directory: dir)
        let first = try await pages.pageData(at: 0)
        let last = try await pages.pageData(at: 2)
        XCTAssertEqual(String(decoding: first, as: UTF8.self), "0001.jpg")
        XCTAssertEqual(String(decoding: last, as: UTF8.self), "0010.jpg")
        do { _ = try await pages.pageData(at: 3); XCTFail("expected an error") } catch {}
    }
}
