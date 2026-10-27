import Foundation

@MainActor
enum LibraryRecommendations {
    static func suggestions(for seed: Manga, in library: [Manga]) -> [Manga] {
        let ignored = Set(["the", "a", "an", "of", "and", "vol", "volume", "chapter"])
        func tokens(_ text: String) -> Set<String> {
            Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 1 && !ignored.contains($0) })
        }
        let words = tokens(seed.title)
        let candidates = library.filter {
            $0.id != seed.id && $0.unreadCount > 0 &&
            (seed.mergeGroupID == nil || $0.mergeGroupID != seed.mergeGroupID)
        }
        func score(_ manga: Manga) -> Int {
            let category = seed.categoryID != nil && manga.categoryID == seed.categoryID ? 8 : 0
            return category + words.intersection(tokens(manga.title)).count * 2 + (manga.hasStarted ? 1 : 0)
        }
        var seen = Set<UUID>()
        return Array(candidates.sorted {
            let a = score($0), b = score($1)
            if a != b { return a > b }
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }.filter { seen.insert($0.mergeGroupID ?? $0.id).inserted }.prefix(12))
    }
}
