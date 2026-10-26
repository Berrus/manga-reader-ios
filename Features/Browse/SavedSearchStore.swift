import Foundation
import Observation

/// Stores search text only; never source code, credentials or downloaded results.
@MainActor @Observable
final class SavedSearchStore {
    static let shared = SavedSearchStore()
    struct Entry: Codable, Identifiable, Equatable {
        var id: UUID
        var sourceID: String
        var query: String
    }
    private(set) var entries: [Entry]
    private let defaults: UserDefaults
    private static let key = "savedSourceSearches.v1"
    static let limit = 100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), data.count <= 1_000_000,
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            var seen = Set<String>()
            entries = decoded.filter {
                !$0.sourceID.isEmpty && !$0.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                $0.query.count <= 200 && seen.insert($0.sourceID + "\u{0}" + $0.query.lowercased()).inserted
            }.prefix(Self.limit).map { $0 }
        } else { entries = [] }
    }

    func searches(for sourceID: String) -> [Entry] { entries.filter { $0.sourceID == sourceID } }
    func contains(sourceID: String, query: String) -> Bool {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return searches(for: sourceID).contains { $0.query.caseInsensitiveCompare(clean) == .orderedSame }
    }
    var isFull: Bool { entries.count >= Self.limit }

    @discardableResult
    func save(sourceID: String, query: String) -> Bool {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceID.isEmpty, !clean.isEmpty, clean.count <= 200, !isFull,
              !contains(sourceID: sourceID, query: clean) else { return false }
        entries.insert(Entry(id: UUID(), sourceID: sourceID, query: clean), at: 0)
        persist()
        return true
    }
    func remove(_ id: UUID) { entries.removeAll { $0.id == id }; persist() }
    private func persist() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
    }
}
