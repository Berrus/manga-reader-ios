import SwiftUI
import SwiftData

struct BrowseView: View {
    @Environment(SourceStore.self) private var store
    private var servers: ServerStore { .shared }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(MangaDexSource(), subtitle: "Official API · Data from MangaDex")
                } header: {
                    Text("Online")
                }

                if !servers.servers.isEmpty {
                    Section("Your servers") {
                        ForEach(servers.servers) { server in
                            if let source = servers.source(for: server) {
                                row(source, subtitle: server.url)
                            } else {
                                Label("\(server.name): check the address in Settings", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if store.enabled && !store.manifests.isEmpty {
                    Section("Custom sources") {
                        ForEach(store.manifests) { manifest in
                            if let source = store.source(for: manifest) {
                                row(source, subtitle: "v\(manifest.version)")
                            } else {
                                Label("\(manifest.name) failed to load", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Browse")
        }
    }

    private func row(_ source: any Source, subtitle: String) -> some View {
        NavigationLink {
            SourceSearchView(source: source)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct SourceSearchView: View {
    let source: any Source
    @State private var query = ""
    @State private var results: [MangaSummary] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var searched = false

    var body: some View {
        List(results) { manga in
            NavigationLink {
                SourceMangaView(source: source, manga: manga)
            } label: {
                HStack(spacing: 12) {
                    RemoteImage(url: manga.coverURL.flatMap(URL.init(string:)), headers: source.imageHeaders)
                    .frame(width: 44, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(manga.title).lineLimit(2)
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if let error {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else if searched && results.isEmpty {
                ContentUnavailableView.search
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query)
        .onSubmit(of: .search) { Task { await search() } }
        .task { if !searched { await search() } }
    }

    private func search() async {
        isLoading = true
        error = nil
        defer { isLoading = false; searched = true }
        do { results = try await source.search(query: query, page: 1) }
        catch { results = []; self.error = error.localizedDescription }
    }
}

struct SourceMangaView: View {
    let source: any Source
    let manga: MangaSummary
    @Environment(\.modelContext) private var context
    @Query private var existing: [Manga]

    init(source: any Source, manga: MangaSummary) {
        self.source = source
        self.manga = manga
        let sourceID = source.id
        let remoteID = manga.id
        _existing = Query(filter: #Predicate<Manga> { $0.sourceID == sourceID && $0.remoteID == remoteID })
    }
    @State private var details: MangaDetails?
    @State private var chapters: [ChapterSummary] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(details?.title ?? manga.title).font(.headline)
                    if let author = details?.author { Text(author).font(.subheadline).foregroundStyle(.secondary) }
                    if let summary = details?.summary { Text(summary).font(.caption) }
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section("Chapters") {
                ForEach(chapters) { chapter in
                    NavigationLink {
                        RemoteReaderView(source: source, chapter: chapter)
                    } label: {
                        Text(chapter.name)
                    }
                }
            }
        }
        .navigationTitle(manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !existing.isEmpty {
                    Label("In library", systemImage: "checkmark.circle.fill")
                } else {
                    Button("Add to library", systemImage: "plus") { addToLibrary() }
                        .disabled(isLoading || chapters.isEmpty)
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
    }

        /// Saves the series and its chapter list so it can be downloaded and read offline.
    private func addToLibrary() {
        let entry = Manga(title: details?.title ?? manga.title, coverData: nil)
        entry.sourceID = source.id
        entry.remoteID = manga.id
        context.insert(entry)
        for item in chapters {
            let chapter = Chapter(name: item.name,
                                  number: item.number ?? LibraryImporter.guessNumber(from: item.name),
                                  fileName: "", pageCount: 0)
            chapter.remoteID = item.id
            context.insert(chapter)
            chapter.manga = entry
        }
        try? context.save()

        let coverString = details?.coverURL ?? manga.coverURL
        let headers = source.imageHeaders
        Task {
            guard let coverString, let url = URL(string: coverString) else { return }
            var request = URLRequest(url: url, timeoutInterval: 20)
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
            let jpeg = await Task.detached(priority: .utility) {
                ImageDownsampler.image(from: data, maxPixel: 500)?.jpegData(compressionQuality: 0.8)
            }.value
            entry.coverData = jpeg
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            async let d = source.details(for: manga)
            async let c = source.chapters(for: manga)
            details = try await d
            chapters = try await c
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Simple vertical reader for online chapters. Offline downloads and the full paged reader
/// for sources are still to do.
struct RemoteReaderView: View {
    let source: any Source
    let chapter: ChapterSummary
    @State private var pages: [PageSource] = []
    @State private var isLoading = true
    @State private var error: String?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let error {
                Text(error).foregroundStyle(.white).padding()
            } else if isLoading {
                ProgressView().tint(.white)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { index in
                            RemotePageView(page: pages[index], displayScale: displayScale)
                        }
                    }
                }
            }
        }
        .navigationTitle(chapter.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        do { pages = try await source.pages(for: chapter) }
        catch { self.error = error.localizedDescription }
    }
}

private struct RemotePageView: View {
    let page: PageSource
    let displayScale: CGFloat
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: ReaderViewModel.webtoonMaxWidth)
                    .frame(maxWidth: .infinity)
            } else if failed {
                Label("Couldn't load page", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.white)
                    .frame(height: 200)
            } else {
                Color.black.frame(height: 500).overlay(ProgressView().tint(.white))
            }
        }
        .task(id: page.url) { await load() }
    }

    private func load() async {
        guard let url = URL(string: page.url), let scheme = url.scheme, ["https", "http"].contains(scheme) else { failed = true; return }
        var request = URLRequest(url: url, timeoutInterval: 30)
        for (key, value) in page.headers ?? [:] { request.setValue(value, forHTTPHeaderField: key) }
        let width = ReaderViewModel.webtoonMaxWidth * displayScale
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard data.count < 30_000_000 else { failed = true; return }
            let decoded = await Task.detached(priority: .userInitiated) {
                ImageDownsampler.image(from: data, fittingWidth: width)
            }.value
            if let decoded { image = decoded } else { failed = true }
        } catch {
            failed = true
        }
    }
}
