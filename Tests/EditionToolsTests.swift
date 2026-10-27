import XCTest
import SwiftData
@testable import MangaReader

@MainActor
final class EditionToolsTests: XCTestCase {
    private var stores: [ModelContainer] = []
    private func context() throws -> ModelContext {
        let schema = Schema([Manga.self, Chapter.self, Category.self, TrackLink.self])
        let store = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        stores.append(store)
        return store.mainContext
    }
    private func book(_ title: String, in context: ModelContext) -> Manga {
        let manga = Manga(title: title, coverData: nil)
        context.insert(manga)
        return manga
    }
    private func chapter(_ name: String, number: Double, in manga: Manga, context: ModelContext) -> Chapter {
        let chapter = Chapter(name: name, number: number, fileName: "owned.cbz", pageCount: 10)
        context.insert(chapter); chapter.manga = manga
        return chapter
    }
    func testMergeAndUnmergePreserveOwnershipProgressCategoriesAndTrackers() throws {
        let context = try context()
        let a = book("A", in: context), b = book("B", in: context)
        a.categoryID = UUID(); b.categoryID = UUID()
        let category = a.categoryID
        let page = chapter("One", number: 1, in: a, context: context)
        page.lastPage = 4; page.isDownloaded = true
        let link = TrackLink(mangaID: a.id, trackerID: "anilist", remoteId: 7, remoteTitle: "A")
        context.insert(link)
        try LibraryMerge.merge([a, b], in: [a, b], context: context)
        XCTAssertNotNil(a.mergeGroupID); XCTAssertEqual(a.mergeGroupID, b.mergeGroupID)
        XCTAssertEqual(page.manga?.id, a.id); XCTAssertEqual(page.lastPage, 4)
        XCTAssertEqual(page.fileName, "owned.cbz"); XCTAssertTrue(page.isDownloaded)
        XCTAssertEqual(a.categoryID, category); XCTAssertEqual(link.mangaID, a.id)
        try LibraryMerge.unmerge(a, in: [a, b], context: context)
        XCTAssertNil(a.mergeGroupID); XCTAssertNil(b.mergeGroupID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Manga>()), 2)
    }
    func testMergingExistingGroupIncludesAllItsEditions() throws {
        let context = try context()
        let a = book("A", in: context), b = book("B", in: context), c = book("C", in: context)
        try LibraryMerge.merge([a, b], in: [a, b, c], context: context)
        try LibraryMerge.merge([a, c], in: [a, b, c], context: context)
        XCTAssertEqual(Set([a, b, c].compactMap(\.mergeGroupID)).count, 1)
    }
    func testFailedMergeRestoresOnlyGroupFields() throws {
        let context = try context()
        let a = book("A", in: context), b = book("B", in: context)
        try context.save()
        a.title = "Unsaved title"
        enum Failure: Error { case save }
        XCTAssertThrowsError(try LibraryMerge.merge([a,b], in: [a,b], context: context,
            save: { _ in throw Failure.save }))
        XCTAssertNil(a.mergeGroupID); XCTAssertNil(b.mergeGroupID)
        XCTAssertEqual(a.title, "Unsaved title")
    }
    func testMigrationSkipsAmbiguousNumbersButAllowsUniqueExactNames() throws {
        let context = try context()
        let manga = book("A", in: context)
        let a = chapter("One A", number: 1, in: manga, context: context)
        _ = chapter("One B", number: 1, in: manga, context: context)
        a.isRead = true
        let plan = SourceMigration.plan(from: manga, to: [
            ChapterSummary(id: "ambiguous", name: "Chapter 1", number: 1),
            ChapterSummary(id: "exact", name: "One A", number: 1)])
        XCTAssertNil(plan.matches["ambiguous"]); XCTAssertEqual(plan.matches["exact"], a.id)
    }
    func testMigrationRetainsOriginalAndDoesNotTransferPartialPageOrFiles() throws {
        let context = try context()
        let original = book("A", in: context)
        let read = chapter("One", number: 1, in: original, context: context)
        read.isRead = true
        let partial = chapter("Two", number: 2, in: original, context: context)
        partial.lastPage = 4
        context.insert(TrackLink(mangaID: original.id, trackerID: "anilist", remoteId: 9, remoteTitle: "A"))
        let migrated = try SourceMigration.copy(original: original,
            destination: MangaSummary(id: "new", title: "New"), sourceID: "fixture",
            chapters: [ChapterSummary(id: "1", name: "Different 1", number: 1),
                       ChapterSummary(id: "2", name: "Different 2", number: 2)],
            context: context, allowed: { _ in true })
        XCTAssertTrue(migrated.sortedChapters[0].isRead)
        XCTAssertFalse(migrated.sortedChapters[1].isRead)
        XCTAssertEqual(migrated.sortedChapters[1].lastPage, 0)
        XCTAssertTrue(migrated.chapters.allSatisfy { $0.fileName.isEmpty && !$0.isDownloaded })
        XCTAssertEqual(partial.lastPage, 4); XCTAssertEqual(original.chapters.count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrackLink>()), 2)
    }
    func testMigrationRejectsUnavailableSourcesAndDuplicateIdentifiers() throws {
        let context = try context()
        let a = book("A", in: context)
        let destination = MangaSummary(id: "b", title: "B")
        let chapters = [ChapterSummary(id: "1", name: "One", number: 1)]
        XCTAssertThrowsError(try SourceMigration.copy(original: a, destination: destination,
            sourceID: "blocked", chapters: chapters, context: context, allowed: { _ in false }))
        XCTAssertThrowsError(try SourceMigration.copy(original: a, destination: destination,
            sourceID: "fixture", chapters: chapters + chapters, context: context, allowed: { _ in true }))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Manga>()), 1)
    }
    func testBackupRoundTripsGroupsAndLegacyVersionTwoStillDecodes() throws {
        let context = try context()
        let a = book("A", in: context), b = book("B", in: context)
        try LibraryMerge.merge([a,b], in: [a,b], context: context)
        let backup = try BackupService.decode(BackupService.encode(BackupService.snapshot(context: context)))
        a.mergeGroupID = nil; b.mergeGroupID = nil
        _ = try BackupService.restore(backup, into: context)
        XCTAssertNotNil(a.mergeGroupID); XCTAssertEqual(a.mergeGroupID, b.mergeGroupID)
        let legacy = Data(#"{"version":2,"createdAt":"2026-10-26T12:00:00Z","categories":[],"series":[],"trackLinks":[]}"#.utf8)
        XCTAssertEqual(try BackupService.decode(legacy).version, 2)
    }
    func testRecommendationsStayLocalExcludeFinishedAndCollapseGroups() throws {
        let context = try context()
        let seed = book("Moon", in: context), related = book("Moon two", in: context)
        let finished = book("Moon finished", in: context), edition = book("Moon edition", in: context)
        _ = chapter("One", number: 1, in: related, context: context)
        _ = chapter("One", number: 1, in: edition, context: context)
        chapter("One", number: 1, in: finished, context: context).isRead = true
        related.mergeGroupID = UUID(); edition.mergeGroupID = related.mergeGroupID
        let result = LibraryRecommendations.suggestions(for: seed, in: [seed, related, finished, edition])
        XCTAssertEqual(result.count, 1); XCTAssertFalse(result.contains { $0.id == finished.id })
    }
    func testFailedMigrationCleansInsertedModelsAndPreservesOriginalEdits() throws {
        let context = try context()
        let a = book("A", in: context)
        _ = chapter("One", number: 1, in: a, context: context)
        try context.save()
        a.title = "Pending edit"
        enum Failure: Error { case save }
        XCTAssertThrowsError(try SourceMigration.copy(original: a,
            destination: MangaSummary(id: "new", title: "B"), sourceID: "fixture",
            chapters: [ChapterSummary(id: "1", name: "One", number: 1)],
            context: context, allowed: { _ in true }, save: { _ in throw Failure.save }))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Manga>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Chapter>()), 1)
        XCTAssertEqual(a.title, "Pending edit")
        XCTAssertEqual(a.chapters.count, 1)
    }
    func testIncompleteBackupGroupNeverHidesAnUnmatchedEdition() throws {
        let context = try context()
        let a = book("A", in: context), b = book("B", in: context)
        try LibraryMerge.merge([a,b], in: [a,b], context: context)
        var backup = try BackupService.snapshot(context: context)
        // Simulate restoring a group containing an edition not present in the library.
        backup.series[1].id = UUID()
        backup.series[1].title = "Missing"
        a.mergeGroupID = nil; b.mergeGroupID = nil
        _ = try BackupService.restore(backup, into: context)
        XCTAssertNil(a.mergeGroupID); XCTAssertNil(b.mergeGroupID)
    }
}
