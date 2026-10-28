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

    @AppStorage("chapterSortDescending") private var chapterSortDescending = false
    @State private var startChapter: ChapterSummary?

    private var coverAddress: URL? { (details?.coverURL ?? manga.coverURL).flatMap(URL.init(string:)) }
    private var allNumbered: Bool { !chapters.isEmpty && chapters.allSatisfy { $0.number != nil } }
    /// Numbered chapters are ordered by number; otherwise the source's own order is kept, because it isn't known.
    private var ordered: [ChapterSummary] {
        let base = allNumbered ? chapters.sorted { ($0.number ?? 0) < ($1.number ?? 0) } : chapters
        return chapterSortDescending && allNumbered ? Array(base.reversed()) : base
    }
    private var firstChapter: ChapterSummary? { allNumbered ? chapters.min { ($0.number ?? 0) < ($1.number ?? 0) } : nil }

    var body: some View {
        List {
            header
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            if !similar.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(similar) { item in
                                NavigationLink {
                                    SourceMangaView(source: source, manga: item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        RemoteImage(url: item.coverURL.flatMap(URL.init(string:)),
                                                    headers: source.imageHeaders, policy: source.accessPolicy)
                                            .frame(width: 96, height: 144)
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.coverRadius, style: .continuous))
                                        Text(item.title).font(.caption).lineLimit(2).frame(width: 96, alignment: .leading)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Similar titles")
                } footer: {
                    Text("Suggested by \(source.name). Only this title's id is sent to ask for them.")
                }
            }
            Section {
                ForEach(ordered) { chapter in
                    NavigationLink {
                        RemoteReaderView(source: source, chapter: chapter) { recordRead(chapter) }
                    } label: {
                        HStack(spacing: 12) {
                            if let number = chapter.number {
                                Text(Self.format(number))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .frame(minWidth: 40)
                                    .padding(.vertical, 6)
                                    .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            Text(chapter.name).lineLimit(2)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("\(chapters.count) chapters")
                    Spacer()
                    if allNumbered {
                        Picker("Chapter order", selection: $chapterSortDescending) {
                            Text("Oldest first").tag(false)
                            Text("Newest first").tag(true)
                        }.pickerStyle(.menu).textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(manga.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $startChapter) { item in
            RemoteReaderView(source: source, chapter: item) { recordRead(item) }
        }
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
        .task { similar = (try? await source.related(to: manga)) ?? [] }
    }

    /// Reading a series that is in the library puts it in History.
    private func recordRead(_ chapter: ChapterSummary) {
        guard let entry = existing.first else { return }
        entry.lastReadAt = .now
        entry.lastReadChapterName = chapter.name
    }

    private static func format(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }

    /// Blurred cover backdrop with the cover, title, source, and the two main actions.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 16) {
                RemoteImage(url: coverAddress, headers: source.imageHeaders, policy: source.accessPolicy)
                    .frame(width: 120, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.coverRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text(details?.title ?? manga.title).font(.title3.bold()).lineLimit(4)
                    if let author = details?.author, !author.isEmpty {
                        Text(author).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Pill(text: source.name, systemImage: "globe")
                        if !chapters.isEmpty { Pill(text: "\(chapters.count) chapters", systemImage: "books.vertical") }
                    }
                }
            }
            HStack(spacing: 10) {
                if let first = firstChapter {
                    Button { startChapter = first } label: {
                        Label("Start reading", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                }
                if existing.isEmpty {
                    Button { addToLibrary() } label: {
                        Label("Add to library", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading || chapters.isEmpty)
                } else {
                    Label("In library", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity).foregroundStyle(Theme.accent)
                }
            }
            .controlSize(.large)
            if let summary = details?.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary).font(.subheadline).lineLimit(showFullSummary ? nil : 3)
                    Button(showFullSummary ? "Show less" : "More") { withAnimation { showFullSummary.toggle() } }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RemoteImage(url: coverAddress, headers: source.imageHeaders, policy: source.accessPolicy)
                    .blur(radius: 30).scaleEffect(1.3)
                Rectangle().fill(.regularMaterial)
            }.clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius + 6, style: .continuous))
        .padding(.horizontal, 16).padding(.vertical, 8)
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
    /// Called once the chapter's pages have loaded, so the caller can record it in History.
    var onOpen: (() -> Void)? = nil
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
                ReaderErrorView(message: error) { reloadID = UUID() }
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
        do {
            pages = try await source.pages(for: chapter)
            onOpen?()
        } catch { self.error = error.localizedDescription }
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
