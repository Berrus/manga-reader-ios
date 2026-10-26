import SwiftUI
import SwiftData

/// "Tracking" rows on the series page. Only shown when AniList is connected.
struct TrackingSection: View {
    let manga: Manga
    @Environment(\.modelContext) private var context
    @Query private var links: [TrackLink]
    @State private var showSearch = false
    @State private var isSyncing = false
    @State private var message: String?

    init(manga: Manga) {
        self.manga = manga
        let id = manga.id
        _links = Query(filter: #Predicate<TrackLink> { $0.mangaID == id })
    }

    private var link: TrackLink? { links.first { $0.trackerID == "anilist" } }

    var body: some View {
        Section("Tracking") {
            if let link {
                VStack(alignment: .leading, spacing: 4) {
                    Label(link.remoteTitle, systemImage: "link")
                    if let synced = link.lastSyncedAt {
                        Text("Synced \(synced.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                Button("Sync now", systemImage: "arrow.triangle.2.circlepath") { sync(link) }
                    .disabled(isSyncing)
                Button("Unlink", systemImage: "link.badge.minus", role: .destructive) {
                    context.delete(link)
                }
            } else {
                Button("Link to AniList", systemImage: "link.badge.plus") { showSearch = true }
            }
        }
        .sheet(isPresented: $showSearch) {
            TrackSearchView(manga: manga) { result in
                let new = TrackLink(mangaID: manga.id, trackerID: "anilist",
                                    remoteId: result.remoteId, remoteTitle: result.title)
                context.insert(new)
                sync(new)
            }
        }
    }

    private func sync(_ link: TrackLink) {
        guard let tracker = TrackerSync.shared.trackers[link.trackerID] else {
            message = "Not connected to AniList."
            return
        }
        isSyncing = true
        message = nil
        Task {
            defer { isSyncing = false }
            do {
                switch try await TrackerSync.shared.reconcile(manga: manga, link: link, tracker: tracker) {
                case .unchanged: message = "Already up to date."
                case .pulled(let n): message = "Marked chapters up to \(Int(n)) as read."
                case .pushed(let n): message = "Sent chapter \(Int(n)) to AniList."
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

struct TrackSearchView: View {
    let manga: Manga
    let onPick: (TrackSearchResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [TrackSearchResult] = []
    @State private var isLoading = false
    @State private var error: String?

    init(manga: Manga, onPick: @escaping (TrackSearchResult) -> Void) {
        self.manga = manga
        self.onPick = onPick
        _query = State(initialValue: manga.title)
    }

    var body: some View {
        NavigationStack {
            List(results) { result in
                Button {
                    onPick(result)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: result.coverURL) { $0.resizable().scaledToFill() } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 40, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading) {
                            Text(result.title).lineLimit(2)
                            if let total = result.totalChapters {
                                Text("\(total) chapters").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if isLoading { ProgressView() }
                else if let error { ContentUnavailableView("Search failed", systemImage: "exclamationmark.triangle", description: Text(error)) }
                else if results.isEmpty { ContentUnavailableView.search }
            }
            .navigationTitle("Link to AniList")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query)
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await search() }
        }
    }

    private func search() async {
        guard let tracker = TrackerSync.shared.trackers["anilist"] else {
            error = "Not connected to AniList."
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { results = try await tracker.search(query) }
        catch { results = []; self.error = error.localizedDescription }
    }
}
