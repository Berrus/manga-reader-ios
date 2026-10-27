import SwiftUI
import SwiftData

struct LibraryEntryView: View {
    let manga: Manga
    @Query private var library: [Manga]
    var body: some View {
        let members = LibraryMerge.members(of: manga, in: library)
        if members.count > 1 { MergedEditionsView(manga: manga, members: members) }
        else { MangaDetailView(manga: manga) }
    }
}

private struct MergedEditionsView: View {
    let manga: Manga
    let members: [Manga]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text("Editions remain separate underneath this group. Choose an edition to read, download, or manage its chapters.")
            }
            ForEach(members) { member in
                NavigationLink {
                    MangaDetailView(manga: member)
                } label: {
                    VStack(alignment: .leading) {
                        Text(member.title)
                        Text("\(member.sourceID ?? "Imported files") · \(member.unreadCount) unread")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button("Unmerge editions") {
                do {
                    try LibraryMerge.unmerge(manga, in: members, context: context)
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(manga.title)
    }
}

struct MergeEntriesView: View {
    let manga: Manga
    @Query(sort: \Manga.title) private var library: [Manga]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<UUID>()
    @State private var error: String?
    private var included: [Manga] {
        let chosen = library.filter { selected.contains($0.id) }
        let groups = Set(chosen.compactMap(\.mergeGroupID))
        return library.filter { selected.contains($0.id) || $0.mergeGroupID.map(groups.contains) == true }
    }
    var body: some View {
        List {
            Section("Choose editions") {
                ForEach(library) { entry in
                    Toggle(isOn: Binding(get: { selected.contains(entry.id) }, set: { value in
                        if value { selected.insert(entry.id) } else { selected.remove(entry.id) }
                    })) {
                        VStack(alignment: .leading) {
                            Text(entry.title)
                            Text(entry.sourceID ?? "Imported files").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Preview: \(included.count) entries") {
                ForEach(included) { Text($0.title) }
                Text("Existing groups expand to include all their editions. Files, categories, trackers and reading progress stay with each edition. Unmerge reverses the grouping.")
                    .font(.footnote)
                Button("Merge entries") {
                    do {
                        try LibraryMerge.merge(included, in: library, context: context)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(included.count < 2)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Merge editions")
        .onAppear { selected.insert(manga.id) }
    }
}

struct LibraryRecommendationsView: View {
    let manga: Manga
    @Query private var library: [Manga]
    var body: some View {
        List {
            Section {
                Text("Suggestions from your existing library, ranked by shared category, title words, and unfinished reading. No reading data is sent to a recommendation service.")
                    .font(.footnote)
            }
            let suggestions = LibraryRecommendations.suggestions(for: manga, in: library)
            if suggestions.isEmpty { Text("No unread suggestions yet.") }
            ForEach(suggestions) { entry in
                NavigationLink { LibraryEntryView(manga: entry) } label: { Text(entry.title) }
            }
        }.navigationTitle("Library suggestions")
    }
}

struct SourceMigrationView: View {
    let manga: Manga
    @Environment(\.modelContext) private var context
    @State private var sourceID = ""
    @State private var query = ""
    @State private var results: [MangaSummary] = []
    @State private var selected: MangaSummary?
    @State private var chapters: [ChapterSummary] = []
    @State private var busy = false
    @State private var error: String?
    @State private var created: Manga?
    @State private var operation: Task<Void, Never>?
    private var sources: [any Source] { SourceRegistry.available }
    private var source: (any Source)? { SourceRegistry.source(id: sourceID) }
    var body: some View {
        Form {
            Section("Destination") {
                Picker("Source", selection: $sourceID) {
                    Text("Choose a source").tag("")
                    ForEach(sources, id: \.id) { Text($0.name).tag($0.id) }
                }.disabled(busy)
                TextField("Search title", text: $query).disabled(busy)
                Button("Search", action: search).disabled(busy || source == nil)
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if let created {
                Section("Added new edition") {
                    NavigationLink { MangaDetailView(manga: created) } label: { Text(created.title) }
                }
            } else if let selected {
                preview(selected)
            } else {
                Section("Results") {
                    ForEach(results) { result in
                        Button(result.title) { review(result) }.disabled(busy)
                    }
                }
            }
        }
        .navigationTitle("Migrate source")
        .onAppear { query = manga.title }
        .onDisappear { operation?.cancel() }
        .onChange(of: sourceID) { _, _ in results = []; selected = nil; chapters = []; created = nil; error = nil }
    }
    private func preview(_ destination: MangaSummary) -> some View {
        let plan = SourceMigration.plan(from: manga, to: chapters)
        return Section("Preview: \(destination.title)") {
            Text("\(chapters.count) chapters · \(plan.matches.count) matched · \(plan.completed) completed · \(plan.skipped) unmatched")
            Text("The original remains in your library. Only completed status is copied. Partial-page positions and downloads remain with the original. Unmatched chapters start unread.")
                .font(.footnote)
            Button("Add edition and copy completed progress") {
                do {
                    created = try SourceMigration.copy(original: manga, destination: destination,
                        sourceID: sourceID, chapters: chapters, context: context)
                } catch { self.error = error.localizedDescription }
            }.disabled(chapters.isEmpty || busy)
            Button("Choose another result") { selected = nil }
        }
    }
    private func search() {
        guard !busy, let source else { return }
        busy = true; error = nil; selected = nil; created = nil; results = []
        let text = query
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let response = try await source.search(query: text, page: 1)
                try Task.checkCancellation()
                var seen = Set<String>()
                results = Array(response.filter { seen.insert($0.id).inserted }.prefix(100))
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func review(_ result: MangaSummary) {
        guard let source else { return }
        busy = true; error = nil
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let response = try await source.chapters(for: result)
                try Task.checkCancellation()
                guard response.count <= 10_000 else { throw LibraryChangeError.ambiguous }
                chapters = response; selected = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
