import XCTest
import SwiftData
import UIKit
import ZIPFoundation
@testable import MangaReader

@MainActor
final class MangaReaderTests: XCTestCase {
    private func chapter(pages: Int = 4) -> Chapter {
        Chapter(name: "Test", number: 1, fileName: UUID().uuidString + ".cbz", pageCount: pages)
    }

    private func container() throws -> ModelContainer {
        let schema = Schema([Manga.self, Chapter.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }

    private func archive(_ entries: [(String, Data)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".cbz")
        let zip = try Archive(url: url, accessMode: .create)
        for (path, data) in entries {
            try zip.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<min(Int(position) + size, data.count))
            }
        }
        return url
    }

    private func imageData(size: CGSize = CGSize(width: 60, height: 90)) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testResumePrefersPartlyReadChapterOverEarlierUnread() {
        let manga = Manga(title: "Series", coverData: nil)
        let early = chapter()
        let later = chapter()
        early.number = 1
        later.number = 2
        later.lastPage = 2
        manga.chapters = [later, early]
        XCTAssertEqual(manga.resumeChapter?.id, later.id)
    }

    func testResumeFallsBackToUnreadThenFirstChapter() {
        let manga = Manga(title: "Series", coverData: nil)
        let first = chapter()
        let second = chapter()
        first.number = 1
        second.number = 2
        first.isRead = true
        manga.chapters = [second, first]
        XCTAssertEqual(manga.resumeChapter?.id, second.id)
        second.isRead = true
        XCTAssertEqual(manga.resumeChapter?.id, first.id)
    }

    func testChapterOrderingAndUnreadCount() {
        let manga = Manga(title: "Series", coverData: nil)
        let a = chapter(), b = chapter(), c = chapter()
        a.number = 12.5
        b.number = 2
        c.number = 12
        b.isRead = true
        manga.chapters = [a, b, c]
        XCTAssertEqual(manga.sortedChapters.map(\.number), [2, 12, 12.5])
        XCTAssertEqual(manga.unreadCount, 2)
    }

    func testChapterNumberUsesLastDecimalNumber() {
        XCTAssertEqual(LibraryImporter.guessNumber(from: "Series Vol 3 Ch 12.5"), 12.5)
        XCTAssertEqual(LibraryImporter.guessNumber(from: "Special chapter"), 0)
    }

    func testOpeningLastPageDoesNotFinishChapter() {
        let item = chapter()
        let vm = ReaderViewModel(chapter: item)
        vm.saveProgress(3, markRead: false)
        XCTAssertEqual(item.lastPage, 3)
        XCTAssertFalse(item.isRead)
    }

    func testTurningToLastPageFinishesChapter() {
        let item = chapter()
        ReaderViewModel(chapter: item).saveProgress(3)
        XCTAssertTrue(item.isRead)
    }

    func testInvalidProgressIsClampedWithoutCompleting() {
        let item = chapter()
        let vm = ReaderViewModel(chapter: item)
        vm.saveProgress(-10)
        XCTAssertEqual(item.lastPage, 0)
        vm.saveProgress(100)
        XCTAssertEqual(item.lastPage, 3)
        XCTAssertFalse(item.isRead)
    }

    func testEmptyChapterDoesNotComplete() {
        let item = chapter(pages: 0)
        ReaderViewModel(chapter: item).saveProgress(0)
        XCTAssertFalse(item.isRead)
    }

    func testOnePageChapterCompletesWithoutInvalidPageIndex() {
        let item = chapter(pages: 1)
        let vm = ReaderViewModel(chapter: item)
        vm.saveProgress(0)
        vm.saveProgress(1)
        XCTAssertEqual(item.lastPage, 0)
        XCTAssertTrue(item.isRead)
    }

    func testArchiveNaturallySortsPagesAndIgnoresMetadata() async throws {
        let url = try archive([
            ("10.png", Data([10])), ("2.png", Data([2])), ("1.png", Data([1])),
            ("__MACOSX/ghost.png", Data([99])), (".hidden.png", Data([99])),
            ("notes.txt", Data([99]))
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let cbz = try CBZArchive(url: url)
        XCTAssertEqual(cbz.pageCount, 3)
        let first = try await cbz.pageData(at: 0)
        let last = try await cbz.pageData(at: 2)
        XCTAssertEqual(first, Data([1]))
        XCTAssertEqual(last, Data([10]))
    }

    func testArchiveRejectsOutOfBoundsPage() async throws {
        let url = try archive([("1.png", Data([1]))])
        defer { try? FileManager.default.removeItem(at: url) }
        let cbz = try CBZArchive(url: url)
        for index in [-1, 1] {
            do {
                _ = try await cbz.pageData(at: index)
                XCTFail("Out-of-range page unexpectedly loaded")
            } catch CBZError.pageOutOfRange {} catch { XCTFail("Wrong error: \(error)") }
        }
    }

    func testArchiveRejectsNoImageEntries() throws {
        let url = try archive([("notes.txt", Data([1]))])
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try CBZArchive(url: url)) { error in
            guard case CBZError.noImages = error else { return XCTFail("Wrong error: \(error)") }
        }
    }

    func testImportCreatesSeriesAndAppendsChapter() async throws {
        let store = try container()
        let context = store.mainContext
        let url = try archive([("1.png", imageData()), ("2.png", imageData())])
        defer {
            try? FileManager.default.removeItem(at: url)
            for manga in (try? context.fetch(FetchDescriptor<Manga>())) ?? [] {
                LibraryImporter.deleteFiles(for: manga)
            }
        }
        try await LibraryImporter.importFile(at: url, into: nil, context: context)
        let manga = try XCTUnwrap(context.fetch(FetchDescriptor<Manga>()).first)
        XCTAssertEqual(manga.chapters.count, 1)
        XCTAssertEqual(manga.chapters.first?.pageCount, 2)
        XCTAssertNotNil(manga.coverData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(manga.chapters.first).fileURL.path))
        try await LibraryImporter.importFile(at: url, into: manga, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Manga>()), 1)
        XCTAssertEqual(manga.chapters.count, 2)
    }

    func testFailedImportLeavesNoDatabaseRecordOrCopiedFile() async throws {
        let store = try container()
        let context = store.mainContext
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: LibraryImporter.booksDirectory.path))
        let url = try archive([("notes.txt", Data([1]))])
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try await LibraryImporter.importFile(at: url, into: nil, context: context)
            XCTFail("Invalid archive imported")
        } catch {}
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Manga>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Chapter>()), 0)
        let after = Set(try FileManager.default.contentsOfDirectory(atPath: LibraryImporter.booksDirectory.path))
        XCTAssertEqual(before, after)
    }

    func testReaderModeCacheDoesNotReuseWrongDecodeSize() async throws {
        let url = try archive([("1.png", imageData(size: CGSize(width: 1200, height: 6000)))])
        defer { try? FileManager.default.removeItem(at: url) }
        let item = chapter(pages: 1)
        try FileManager.default.copyItem(at: url, to: item.fileURL)
        defer { try? FileManager.default.removeItem(at: item.fileURL) }
        let vm = ReaderViewModel(chapter: item)
        let screen = await vm.image(at: 0, fit: .screen)
        let width = await vm.image(at: 0, fit: .width)
        let screenImage = try XCTUnwrap(screen)
        let widthImage = try XCTUnwrap(width)
        XCTAssertFalse(screenImage === widthImage, "Reader modes must not share the same cached object")
        let cachedScreen = await vm.image(at: 0, fit: .screen)
        XCTAssertTrue(screenImage === cachedScreen)
        vm.clearCache()
        let reloaded = await vm.image(at: 0, fit: .screen)
        XCTAssertNotNil(reloaded)
        XCTAssertFalse(screenImage === reloaded)
    }

    func testCorruptPageReportsFailureInsteadOfEndlessLoading() async throws {
        let url = try archive([("1.png", Data("not an image".utf8))])
        defer { try? FileManager.default.removeItem(at: url) }
        let item = chapter(pages: 1)
        try FileManager.default.copyItem(at: url, to: item.fileURL)
        defer { try? FileManager.default.removeItem(at: item.fileURL) }
        let vm = ReaderViewModel(chapter: item)
        let image = await vm.image(at: 0, fit: .screen)
        XCTAssertNil(image)
        XCTAssertTrue(vm.failedPages.contains(0))
    }

    func testDownsamplingPreservesAspectRatioAndBounds() throws {
        let data = imageData(size: CGSize(width: 100, height: 400))
        let image = try XCTUnwrap(ImageDownsampler.image(from: data, maxPixel: 200))
        XCTAssertEqual(image.size.height, 200, accuracy: 1)
        XCTAssertEqual(image.size.width, 50, accuracy: 1)
        XCTAssertNil(ImageDownsampler.image(from: Data(), maxPixel: 200))
    }
}
