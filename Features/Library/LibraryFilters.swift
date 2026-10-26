import Foundation
import SwiftData

enum LibraryReadingFilter: String, CaseIterable, Identifiable {
    case all, notStarted, reading, completed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Any reading status"
        case .notStarted: return "Not started"
        case .reading: return "Reading"
        case .completed: return "Completed"
        }
    }
    func includes(_ manga: Manga) -> Bool {
        switch self {
        case .all: return true
        case .notStarted: return !manga.hasStarted
        case .reading: return manga.hasStarted && manga.unreadCount > 0
        case .completed: return !manga.chapters.isEmpty && manga.unreadCount == 0
        }
    }
}

enum LibraryOperations {
    /// Restore only this operation's fields on failure, preserving unrelated edits.
    @MainActor
    static func move(_ titles: [Manga], to categoryID: UUID?, context: ModelContext,
                     save: ((ModelContext) throws -> Void)? = nil) throws {
        let previous = titles.map { ($0, $0.categoryID) }
        titles.forEach { $0.categoryID = categoryID }
        do { if let save { try save(context) } else { try context.save() } }
        catch {
            previous.forEach { $0.0.categoryID = $0.1 }
            throw error
        }
    }
}
