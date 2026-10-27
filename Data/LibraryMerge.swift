import Foundation
import SwiftData

enum LibraryChangeError: LocalizedError {
    case chooseTwo, unavailable, duplicate, ambiguous
    var errorDescription: String? {
        switch self {
        case .chooseTwo: return "Choose at least two library entries."
        case .unavailable: return "The destination source is unavailable in this build."
        case .duplicate: return "This destination is already in your library."
        case .ambiguous: return "The chapter list contains invalid or duplicate identifiers."
        }
    }
}

@MainActor
enum LibraryMerge {
    static func members(of manga: Manga, in library: [Manga]) -> [Manga] {
        guard let group = manga.mergeGroupID else { return [manga] }
        return library.filter { $0.mergeGroupID == group }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
    /// No models, chapter ownership, files or tracker links are moved or deleted.
    static func merge(_ selected: [Manga], in library: [Manga], context: ModelContext,
                      save: ((ModelContext) throws -> Void)? = nil) throws {
        let ids = Set(selected.map(\.id))
        let groups = Set(selected.compactMap(\.mergeGroupID))
        let members = library.filter { ids.contains($0.id) || $0.mergeGroupID.map(groups.contains) == true }
        guard members.count >= 2 else { throw LibraryChangeError.chooseTwo }
        let previous = members.map { ($0, $0.mergeGroupID) }
        let group = UUID()
        members.forEach { $0.mergeGroupID = group }
        do { if let save { try save(context) } else { try context.save() } }
        catch { previous.forEach { $0.0.mergeGroupID = $0.1 }; throw error }
    }
    static func unmerge(_ manga: Manga, in library: [Manga], context: ModelContext,
                        save: ((ModelContext) throws -> Void)? = nil) throws {
        let members = members(of: manga, in: library)
        let previous = members.map { ($0, $0.mergeGroupID) }
        members.forEach { $0.mergeGroupID = nil }
        do { if let save { try save(context) } else { try context.save() } }
        catch { previous.forEach { $0.0.mergeGroupID = $0.1 }; throw error }
    }
}
