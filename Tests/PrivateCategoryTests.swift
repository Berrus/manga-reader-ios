import XCTest
import SwiftData
@testable import MangaReader

@MainActor
final class PrivateCategoryTests: XCTestCase {
    private func context() throws -> ModelContext {
        let schema = Schema([Manga.self, Chapter.self, TrackLink.self, Category.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ]).mainContext
    }

    private func library(_ context: ModelContext) -> (all: [Manga], categories: [Category]) {
        let hidden = Category(name: "Private", order: 0); hidden.isPrivate = true
        let open = Category(name: "Open", order: 1)
        [hidden, open].forEach(context.insert)
        let a = Manga(title: "Secret", coverData: nil); a.categoryID = hidden.id
        let b = Manga(title: "Shown", coverData: nil); b.categoryID = open.id
        let c = Manga(title: "Loose", coverData: nil)
        [a, b, c].forEach(context.insert)
        return ([a, b, c], [hidden, open])
    }

    func testPrivateSeriesAreHiddenWhileLocked() throws {
        let (all, categories) = library(try context())
        let titles = PrivacyFilter.visible(all, categories: categories, unlocked: false).map(\.title)
        XCTAssertEqual(Set(titles), ["Shown", "Loose"])
    }

    func testEverythingShowsOnceUnlocked() throws {
        let (all, categories) = library(try context())
        XCTAssertEqual(PrivacyFilter.visible(all, categories: categories, unlocked: true).count, 3)
    }

    func testNoPrivateCategoriesMeansNothingIsHidden() throws {
        let (all, categories) = library(try context())
        categories.forEach { $0.isPrivate = false }
        XCTAssertEqual(PrivacyFilter.visible(all, categories: categories, unlocked: false).count, 3)
    }

    func testBackupKeepsPrivacyAndNeverRevealsAnExistingPrivateCategory() throws {
        let source = try context()
        _ = library(source)
        let data = try BackupService.encode(BackupService.snapshot(context: source))

        let target = try context()
        let existing = Category(name: "Private", order: 0)   // public here, private in the backup
        target.insert(existing)
        let manga = Manga(title: "Secret", coverData: nil); target.insert(manga)
        _ = try BackupService.restore(try BackupService.decode(data), into: target)
        XCTAssertTrue(existing.isPrivate, "restoring a backup should be able to make a category private")

        let privateHere = Category(name: "Open", order: 5); privateHere.isPrivate = true
        target.insert(privateHere)
        _ = try BackupService.restore(try BackupService.decode(data), into: target)
        XCTAssertTrue(privateHere.isPrivate, "restoring a public entry must not reveal a private category")
    }
}
