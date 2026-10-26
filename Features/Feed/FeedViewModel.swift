import Foundation
import Observation

@MainActor @Observable
final class FeedViewModel {
    struct Section: Identifiable {
        let id: UUID
        let sourceID: String
        let query: String
        var results: [MangaSummary] = []
        var error: String?
        var isLoading = true
    }
    private(set) var sections: [Section] = []
    private(set) var isLoading = false
    private var generation = 0
    private let resolve: @MainActor (String) -> (any Source)?
    init(resolve: @escaping @MainActor (String) -> (any Source)? = { SourceRegistry.source(id: $0) }) {
        self.resolve = resolve
    }
    func load(_ entries: [SavedSearchStore.Entry]) async {
        generation += 1
        let revision = generation
        let entries = Array(entries.prefix(8))
        sections = entries.map { Section(id: $0.id, sourceID: $0.sourceID, query: $0.query) }
        isLoading = true
        defer { if revision == generation { isLoading = false } }
        // Three concurrent calls at most; each source still uses its bounded transport.
        for start in stride(from: 0, to: entries.count, by: 3) {
            guard !Task.isCancelled, revision == generation else { return }
            let batch = entries[start..<min(start + 3, entries.count)].map { ($0, resolve($0.sourceID)) }
            await withTaskGroup(of: Section.self) { group in
                for (entry, source) in batch {
                    group.addTask {
                        var section = Section(id: entry.id, sourceID: entry.sourceID, query: entry.query,
                                              isLoading: false)
                        guard let source else { section.error = "Source unavailable. Check Settings."; return section }
                        do {
                            let response = try await source.search(query: entry.query, page: 1)
                            try Task.checkCancellation()
                            var seen = Set<String>()
                            section.results = Array(response.filter { seen.insert($0.id).inserted }.prefix(20))
                        } catch { section.error = error.localizedDescription }
                        return section
                    }
                }
                for await section in group {
                    guard !Task.isCancelled, revision == generation else { group.cancelAll(); continue }
                    if let index = sections.firstIndex(where: { $0.id == section.id }) { sections[index] = section }
                }
            }
        }
    }
}
