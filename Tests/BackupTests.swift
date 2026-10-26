import XCTest
import SwiftData
@testable import MangaReader

@MainActor
final class BackupTests: XCTestCase {
    private var retainedStores: [ModelContainer] = []
    private func context() throws -> ModelContext {
        let schema = Schema([Manga.self, Chapter.self, TrackLink.self, Category.self])
        let store = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        retainedStores.append(store)
        return store.mainContext
    }

    private func series(_ title: String, in context: ModelContext, read: Bool, lastPage: Int) -> Manga {
        let manga = Manga(title: title, coverData: nil)
        context.insert(manga)
        let chapter = Chapter(name: "Ch 1", number: 1, fileName: UUID().uuidString, pageCount: 10)
        context.insert(chapter)
        chapter.manga = manga
        chapter.isRead = read
        chapter.lastPage = lastPage
        return manga
    }

    func testRestoreMatchesByTitleAndKeepsProgressForward() throws {
        let source = try context()
        let original = series("My Series", in: source, read: true, lastPage: 9)
        let category = Category(name: "Favorites", order: 0)
        source.insert(category)
        original.categoryID = category.id
        let data = try BackupService.encode(try BackupService.snapshot(context: source))

        let target = try context()
        let reimported = series("my series", in: target, read: false, lastPage: 3)
        let summary = try BackupService.restore(try BackupService.decode(data), into: target)

        XCTAssertEqual(summary.series, 1)
        XCTAssertEqual(summary.categories, 1)
        XCTAssertTrue(reimported.chapters[0].isRead)
        XCTAssertEqual(reimported.chapters[0].lastPage, 9)
        XCTAssertNotNil(reimported.categoryID)
    }

    func testRestoreNeverRewindsProgress() throws {
        let source = try context()
        _ = series("Series", in: source, read: false, lastPage: 2)
        let data = try BackupService.encode(try BackupService.snapshot(context: source))

        let target = try context()
        let local = series("Series", in: target, read: true, lastPage: 8)
        _ = try BackupService.restore(try BackupService.decode(data), into: target)
        XCTAssertTrue(local.chapters[0].isRead)
        XCTAssertEqual(local.chapters[0].lastPage, 8)
    }

    func testKomgaPageURLsConvertUnsupportedFormats() throws {
        let base = URL(string: "http://server:25600")!
        let jpeg = KomgaPage(number: 1, mediaType: "image/jpeg")
        let avif = KomgaPage(number: 2, mediaType: "image/avif")
        XCTAssertEqual(KomgaSource.pageURL(base: base, bookID: "b", page: jpeg).absoluteString,
                       "http://server:25600/api/v1/books/b/pages/1")
        XCTAssertEqual(KomgaSource.pageURL(base: base, bookID: "b", page: avif).absoluteString,
                       "http://server:25600/api/v1/books/b/pages/2?convert=jpeg")
    }

    func testMangaDexDedupesChaptersAndDropsOffSiteOnes() throws {
        let json = """
        [{"id":"a","attributes":{"chapter":"1","title":"Start","pages":10,"externalUrl":null}},
         {"id":"b","attributes":{"chapter":"1","title":null,"pages":10,"externalUrl":null}},
         {"id":"c","attributes":{"chapter":"2","title":null,"pages":0,"externalUrl":null}},
         {"id":"d","attributes":{"chapter":"3","title":null,"pages":5,"externalUrl":"https://example.com"}},
         {"id":"e","attributes":{"chapter":"4","title":null,"pages":5,"externalUrl":null}}]
        """
        let items = try JSONDecoder().decode([MangaDexSource.ChapterItem].self, from: Data(json.utf8))
        let chapters = MangaDexSource.chapterList(from: items)
        XCTAssertEqual(chapters.map(\.id), ["a", "e"])
        XCTAssertEqual(chapters.first?.name, "Ch. 1 – Start")
    }
}
