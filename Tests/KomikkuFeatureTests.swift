import XCTest
import SwiftData
@testable import MangaReader

@MainActor
final class KomikkuFeatureTests: XCTestCase {
    private func defaults() -> (UserDefaults, String) {
        let name = "FolioSearchTests-" + UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }
    func testSavedSearchSurvivesRelaunchAndIsIsolatedBySource() {
        let (defaults, name) = defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SavedSearchStore(defaults: defaults)
        XCTAssertTrue(store.save(sourceID: "one", query: "  Moon  "))
        XCTAssertFalse(store.save(sourceID: "one", query: "moon"))
        XCTAssertTrue(store.save(sourceID: "two", query: "Moon"))
        let restored = SavedSearchStore(defaults: defaults)
        XCTAssertEqual(restored.searches(for: "one").map(\.query), ["Moon"])
        XCTAssertEqual(restored.searches(for: "two").count, 1)
        restored.remove(restored.searches(for: "one")[0].id)
        XCTAssertTrue(SavedSearchStore(defaults: defaults).searches(for: "one").isEmpty)
        XCTAssertEqual(SavedSearchStore(defaults: defaults).searches(for: "two").count, 1)
    }
    func testSavedSearchRejectsEmptyOversizeAndCapacityOverflow() {
        let (defaults, name) = defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SavedSearchStore(defaults: defaults)
        XCTAssertFalse(store.save(sourceID: "one", query: " \n "))
        XCTAssertFalse(store.save(sourceID: "", query: "Moon"))
        XCTAssertFalse(store.save(sourceID: "one", query: String(repeating: "x", count: 201)))
        for i in 0..<SavedSearchStore.limit {
            XCTAssertTrue(store.save(sourceID: "one", query: "Search \(i)"))
        }
        XCTAssertFalse(store.save(sourceID: "one", query: "Overflow"))
        XCTAssertEqual(SavedSearchStore(defaults: defaults).entries.count, SavedSearchStore.limit)
    }
    func testMalformedSavedSearchStorageDoesNotBreakBrowse() {
        let (defaults, name) = defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("not JSON".utf8), forKey: "savedSourceSearches.v1")
        XCTAssertTrue(SavedSearchStore(defaults: defaults).entries.isEmpty)
    }
    func testReadingFiltersDistinguishEmptyPartialAndCompletedSeries() {
        let empty = Manga(title: "Empty", coverData: nil)
        XCTAssertTrue(LibraryReadingFilter.notStarted.includes(empty))
        XCTAssertFalse(LibraryReadingFilter.completed.includes(empty))
        let manga = Manga(title: "Book", coverData: nil)
        let chapter = Chapter(name: "One", number: 1, fileName: "", pageCount: 4)
        manga.chapters = [chapter]
        XCTAssertTrue(LibraryReadingFilter.notStarted.includes(manga))
        chapter.lastPage = 1
        XCTAssertTrue(LibraryReadingFilter.reading.includes(manga))
        XCTAssertFalse(LibraryReadingFilter.notStarted.includes(manga))
        chapter.isRead = true
        XCTAssertTrue(LibraryReadingFilter.completed.includes(manga))
        XCTAssertFalse(LibraryReadingFilter.reading.includes(manga))
    }
    func testFailedBulkMoveRestoresCategoriesAndKeepsUnrelatedEdit() throws {
        let schema = Schema([Manga.self, Chapter.self, Category.self, TrackLink.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let context = container.mainContext
        let first = Manga(title: "First", coverData: nil)
        let second = Manga(title: "Second", coverData: nil)
        let previous = UUID()
        first.categoryID = previous
        context.insert(first); context.insert(second)
        try context.save()
        first.title = "Pending edit"
        enum Failure: Error { case save }
        XCTAssertThrowsError(try LibraryOperations.move([first, second], to: UUID(), context: context,
            save: { _ in throw Failure.save }))
        XCTAssertEqual(first.categoryID, previous)
        XCTAssertNil(second.categoryID)
        XCTAssertEqual(first.title, "Pending edit")
        let destination = UUID()
        try LibraryOperations.move([first, second], to: destination, context: context)
        XCTAssertEqual(first.categoryID, destination)
        XCTAssertEqual(second.categoryID, destination)
        withExtendedLifetime(container) {}
    }
}
