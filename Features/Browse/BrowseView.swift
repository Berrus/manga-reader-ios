import SwiftUI
import SwiftData

struct BrowseView: View {
    @Environment(SourceStore.self) private var store
    #if !APP_STORE
    @State private var paperbackStore = PaperbackStore.shared
    #endif
    @State private var sourceQuery = ""
    private func matches(_ name: String) -> Bool { sourceQuery.isEmpty || name.localizedCaseInsensitiveContains(sourceQuery) }
    private var servers: ServerStore { .shared }
    private var komgaServers: [ServerConfig] { servers.servers.filter { $0.kind != .suwayomi && matches($0.name) } }
    private var suwayomiServers: [ServerConfig] {
        DistributionPolicy.allowsSuwayomi ? servers.servers.filter { $0.kind == .suwayomi && matches($0.name) } : []
    }

    var body: some View {
        NavigationStack {
            List {
                if !komgaServers.isEmpty {
                    Section("Your servers") {
                        ForEach(komgaServers) { server in
                            if let source = servers.source(for: server) {
                                row(source, subtitle: server.url)
                            } else {
                                Label("\(server.name): check the address in Settings", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !suwayomiServers.isEmpty {
                    Section {
                        ForEach(suwayomiServers) { server in
                            NavigationLink {
                                SuwayomiSourcesView(server: server)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name)
                                    Text(server.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    } header: {
                        Text("Suwayomi servers")
                    } footer: {
                        Text("Content comes from the extensions installed on your own server.")
                    }
                }
                #if !APP_STORE
                if DistributionPolicy.allowsScriptedSources && paperbackStore.enabled && paperbackStore.installed.contains(where: { paperbackStore.isEnabled($0) }) {
                    Section("Paperback extensions") {
                        ForEach(paperbackStore.installed.filter { paperbackStore.isEnabled($0) && matches($0.name) }) { info in
                            if let source = paperbackStore.source(for: info) {
                                row(source, subtitle: "v\(info.version)")
                            } else {
                                Label("\(info.name) failed to load", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                #endif
                if DistributionPolicy.allowsCustomSources && store.enabled && !store.manifests.isEmpty {
                    Section("Custom sources") {
                        ForEach(store.manifests.filter { matches($0.name) }) { manifest in
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
            .searchable(text: $sourceQuery, prompt: "Search sources")
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
    @State private var submittedQuery = ""
    @State private var searchRevision = 0
    @State private var savedSearches = SavedSearchStore.shared
    @State private var results: [MangaSummary] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var searched = false
    @State private var nextPage = 2
    @State private var canLoadMore = false
    @State private var loadingMore = false
    @State private var moreError: String?
    #if !APP_STORE
    @State private var discovery: [PaperbackSource.DiscoverySection] = []
    @State private var discoveryError: String?
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !savedSearches.searches(for: source.id).isEmpty {
                    savedSearchChips
                }
                #if !APP_STORE
                if submittedQuery.isEmpty {
                    ForEach(discovery) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title).font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(section.items, id: \.mangaId) { item in
                                        let manga = MangaSummary(id: item.mangaId, title: item.title, coverURL: item.imageUrl)
                                        NavigationLink {
                                            SourceMangaView(source: source, manga: manga)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 5) {
                                                RemoteImage(url: item.imageUrl.flatMap(URL.init(string:)),
                                                            headers: source.imageHeaders, policy: source.accessPolicy)
                                                    .frame(width: 120, height: 180)
                                                    .clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                                Text(item.title).font(.subheadline).lineLimit(2)
                                                    .foregroundStyle(.primary)
                                                if let subtitle = item.subtitle {
                                                    Text(subtitle).font(.caption).lineLimit(1)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }.frame(width: 120, alignment: .leading)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    if let discoveryError {
                        Text(discoveryError).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                #endif
                if !results.isEmpty {
                    HStack {
                        Text("Results")
                        Spacer()
                        Text("\(results.count) loaded")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105, maximum: 155), spacing: 12)], alignment: .leading, spacing: 16) {
                        ForEach(results) { manga in
                            NavigationLink {
                                SourceMangaView(source: source, manga: manga)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    RemoteImage(url: manga.coverURL.flatMap(URL.init(string:)),
                                                headers: source.imageHeaders, policy: source.accessPolicy)
                                        .aspectRatio(2.0 / 3.0, contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(manga.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(manga.title)
                        }
                    }
                }
                if !isLoading && !results.isEmpty && canLoadMore {
                    Button(loadingMore ? "Loading…" : "Load more") {
                        Task { await loadMore() }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(loadingMore)
                    if let moreError { Text(moreError).foregroundStyle(.red) }
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let error {
                    ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                    Button("Try again") { submit(submittedQuery) }
                } else if searched && results.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .padding()
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query)
        .onSubmit(of: .search) { submit(query) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    savedSearches.save(sourceID: source.id, query: query)
                } label: {
                    Image(systemName: savedSearches.contains(sourceID: source.id, query: query)
                          ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel("Save search")
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          query.trimmingCharacters(in: .whitespacesAndNewlines).count > 200 ||
                          savedSearches.isFull || savedSearches.contains(sourceID: source.id, query: query))
            }
        }
        .task(id: searchRevision) { await search(submittedQuery, revision: searchRevision) }
        #if !APP_STORE
        .task {
            guard let paperback = source as? PaperbackSource else { return }
            do { discovery = try await paperback.discover() }
            catch { discoveryError = "Discovery unavailable: " + error.localizedDescription }
        }
        #endif
    }

    private var savedSearchChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(savedSearches.searches(for: source.id)) { entry in
                    Button { submit(entry.query) } label: {
                        Label(entry.query, systemImage: "magnifyingglass")
                            .font(.subheadline).lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search for \(entry.query)")
                    .contextMenu {
                        Button("Remove saved search", systemImage: "trash", role: .destructive) {
                            savedSearches.remove(entry.id)
                        }
                    }
                }
            }
        }
    }

    private func submit(_ text: String) {
        query = text
        submittedQuery = text.trimmingCharacters(in: .whitespacesAndNewlines)
        searchRevision += 1
    }

    private func search(_ text: String, revision: Int) async {
        isLoading = true
        error = nil
        results = []
        nextPage = 2
        canLoadMore = false
        moreError = nil
        defer {
            if revision == searchRevision { isLoading = false; searched = true }
        }
        do {
            let response = try await source.search(query: text, page: 1)
            try Task.checkCancellation()
            guard revision == searchRevision else { return }
            results = response
            canLoadMore = !response.isEmpty
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, revision == searchRevision else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !loadingMore, canLoadMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let revision = searchRevision
        let page = nextPage
        let text = submittedQuery
        moreError = nil
        do {
            let response = try await source.search(query: text, page: page)
            guard revision == searchRevision else { return }
            var existing = Set(results.map(\.id))
            let newItems = response.filter { existing.insert($0.id).inserted }
            results.append(contentsOf: newItems)
            nextPage = page + 1
            canLoadMore = !newItems.isEmpty
        } catch {
            guard revision == searchRevision else { return }
            moreError = error.localizedDescription
        }
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
    @State private var showFullSummary = false
    @State private var details: MangaDetails?
    @State private var similar: [MangaSummary] = []
    @State private var chapters: [ChapterSummary] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    RemoteImage(url: (details?.coverURL ?? manga.coverURL).flatMap(URL.init(string:)), headers: source.imageHeaders, policy: source.accessPolicy)
                        .frame(width: 90, height: 135).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(details?.title ?? manga.title).font(.headline)
                        Text(source.name).font(.subheadline).foregroundStyle(.secondary)
                        if let author = details?.author { Text(author).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                if let summary = details?.summary, !summary.isEmpty {
                    Text(summary).font(.subheadline).lineLimit(showFullSummary ? nil : 4)
                    Button(showFullSummary ? "Show less" : "Read more") { showFullSummary.toggle() }
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            if !similar.isEmpty {
                Section {
                    ForEach(similar) { item in
                        NavigationLink {
                            SourceMangaView(source: source, manga: item)
                        } label: {
                            HStack(spacing: 12) {
                                RemoteImage(url: item.coverURL.flatMap(URL.init(string:)),
                                            headers: source.imageHeaders, policy: source.accessPolicy)
                                    .frame(width: 36, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Text(item.title).lineLimit(2)
                            }
                        }
                    }
                } header: {
                    Text("Similar titles")
                } footer: {
                    Text("Suggested by \(source.name). Only this title's id is sent to ask for them.")
                }
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
        .task { similar = (try? await source.related(to: manga)) ?? [] }
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
        let policy = source.accessPolicy
        Task {
            guard let coverString, let url = URL(string: coverString) else { return }
            var request = URLRequest(url: url, timeoutInterval: 20)
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            guard let (data, _) = try? await SourceTransport.load(request, policy: policy, maxBytes: 30_000_000) else { return }
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
    @State private var showControls = true
    @State private var reloadID = UUID()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let error {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(.white)
                    Button("Retry") { reloadID = UUID() }.buttonStyle(.borderedProminent)
                }.padding()
            } else if isLoading {
                ProgressView().tint(.white)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { index in
                            RemotePageView(page: pages[index], displayScale: displayScale, policy: source.accessPolicy)
                        }
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { withAnimation { showControls.toggle() } })
            }
        }
        .navigationTitle(chapter.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showControls ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!showControls)
        .task(id: reloadID) { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { pages = try await source.pages(for: chapter) }
        catch { self.error = error.localizedDescription }
    }
}

private struct RemotePageView: View {
    let page: PageSource
    let displayScale: CGFloat
    let policy: SourceAccessPolicy
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retryID = UUID()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: ReaderViewModel.webtoonMaxWidth)
                    .frame(maxWidth: .infinity)
            } else if failed {
                VStack {
                    Label("Couldn't load page", systemImage: "exclamationmark.triangle").foregroundStyle(.white)
                    Button("Retry") { failed = false; retryID = UUID() }.buttonStyle(.borderedProminent)
                }.frame(height: 200)
            } else {
                Color.black.frame(height: 500).overlay(ProgressView().tint(.white))
            }
        }
        .task(id: "\(page.url)-\(retryID)") { await load() }
    }

    private func load() async {
        guard let url = URL(string: page.url), policy.allows(url) else { failed = true; return }
        var request = URLRequest(url: url, timeoutInterval: 30)
        for (key, value) in page.headers ?? [:] { request.setValue(value, forHTTPHeaderField: key) }
        let width = ReaderViewModel.webtoonMaxWidth * displayScale
        do {
            let (data, _) = try await SourceTransport.load(request, policy: policy, maxBytes: 30_000_000)
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
