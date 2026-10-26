import SwiftUI

/// An opt-in feed of the user's saved queries, not an unlicensed bundled catalog.
struct FeedView: View {
    @State private var saved = SavedSearchStore.shared
    @State private var vm = FeedViewModel()
    @State private var didLoad = false
    var body: some View {
        NavigationStack {
            List {
                if saved.entries.isEmpty {
                    ContentUnavailableView("Build your feed", systemImage: "rectangle.stack",
                        description: Text("Save a search in Browse to add it here. Your eight most recent saved searches appear in the feed."))
                } else if !didLoad {
                    Section {
                        Text("Load results from your saved sources when you're ready.")
                        Button("Load feed") { didLoad = true }
                    }
                } else {
                    ForEach(vm.sections) { section in
                        Section(section.query) {
                            if section.isLoading {
                                ProgressView()
                            } else if let error = section.error {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else if section.results.isEmpty {
                                Text("No results").foregroundStyle(.secondary)
                            } else if let source = SourceRegistry.source(id: section.sourceID) {
                                ForEach(section.results) { manga in
                                    NavigationLink {
                                        SourceMangaView(source: source, manga: manga)
                                    } label: {
                                        HStack(spacing: 12) {
                                            RemoteImage(url: manga.coverURL.flatMap(URL.init(string:)),
                                                        headers: source.imageHeaders, policy: source.accessPolicy)
                                                .frame(width: 40, height: 60).clipped()
                                            Text(manga.title).lineLimit(2)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text("Showing up to 20 results for each of your eight most recent saved searches.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Feed")
            .task(id: didLoad ? saved.entries.map(\.id) : []) {
                if didLoad { await vm.load(saved.entries) }
            }
            .refreshable {
                if didLoad { await vm.load(saved.entries) } else { didLoad = true }
            }
        }
    }
}
