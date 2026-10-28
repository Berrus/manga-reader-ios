import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, title, unread, lastRead
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: return "Recently added"
        case .title: return "Title"
        case .unread: return "Unread"
        case .lastRead: return "Last read"
        }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Manga.addedAt, order: .reverse) private var allLibrary: [Manga]
    private var lock: PrivacyLock { .shared }
    private var library: [Manga] {
        PrivacyFilter.visible(allLibrary, categories: categories, unlocked: lock.isUnlocked)
    }
    private var shownCategories: [Category] { categories.filter { !$0.isPrivate || lock.isUnlocked } }
    @Query(sort: \Category.order) private var categories: [Category]
    @State private var selectedCategory: UUID?
    @AppStorage("librarySort") private var sortRaw = LibrarySort.recent.rawValue
    @AppStorage("libraryUnreadOnly") private var unreadOnly = false
    @AppStorage("libraryReadingFilter") private var readingFilterRaw = LibraryReadingFilter.all.rawValue
    @AppStorage("libraryOfflineOnly") private var offlineOnly = false
    @State private var isSelecting = false
    @State private var selected: Set<UUID> = []
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var search = ""
    @State private var updater = LibraryUpdater.shared
    @AppStorage("appearance.mode") private var appearanceMode = "system"

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 18, alignment: .top)]

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recent }

    private var readingFilter: LibraryReadingFilter { LibraryReadingFilter(rawValue: readingFilterRaw) ?? .all }
    private var hasFilters: Bool { unreadOnly || offlineOnly || readingFilter != .all }

    private var visible: [Manga] {
        var items = library
        if !search.isEmpty { items = items.filter { $0.title.localizedCaseInsensitiveContains(search) } }
        if let selectedCategory { items = items.filter { $0.categoryID == selectedCategory } }
        if unreadOnly { items = items.filter { $0.unreadCount > 0 } }
        items = items.filter { readingFilter.includes($0) }
        if offlineOnly { items = items.filter { $0.chapters.contains { !$0.isRemote || $0.isDownloaded } } }
        switch sort {
        case .recent: break
        case .title: items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .unread: items.sort { $0.unreadCount > $1.unreadCount }
        case .lastRead: items.sort { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
        }
        var seenGroups = Set<UUID>()
        return items.filter { seenGroups.insert($0.mergeGroupID ?? $0.id).inserted }
    }

    private var continueReading: [Manga] {
        library.filter { $0.chapters.contains { $0.inProgress } }
    }

    var body: some View {
        NavigationStack {
            libraryContent
            .background(appearanceMode == "amoled" ? Color.black : Color.clear)
            .navigationTitle("Library")
            .searchable(text: $search, prompt: "Search library")
            .navigationDestination(for: Manga.self) { LibraryEntryView(manga: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack { sortMenu; privacyButton }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if !library.isEmpty {
                            Button(isSelecting ? "Done" : "Select") {
                                isSelecting.toggle()
                                selected.removeAll()
                            }.accessibilityIdentifier("librarySelection")
                        }
                        Button("Import", systemImage: "plus") { showImporter = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { selectionBar }
            }
            .onChange(of: visible.map(\.id)) { _, ids in selected.formIntersection(Set(ids)) }
            .onChange(of: lock.isUnlocked) { _, unlocked in
                if !unlocked, let id = selectedCategory, categories.first(where: { $0.id == id })?.isPrivate == true {
                    selectedCategory = nil
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: UTType.comicArchives,
                          allowsMultipleSelection: true) { result in
                handleImport(result)
            }
            .alert("Library action failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var libraryContent: some View {
            Group {
                if library.isEmpty {
                    ContentUnavailableView {
                        Label("Your library is empty", systemImage: "books.vertical")
                    } description: {
                        Text("Import CBZ files from the Files app to start reading.")
                    } actions: {
                        Button("Import files") { showImporter = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if updater.isRunning {
                                VStack(alignment: .leading) {
                                    Text("Updating: \(updater.currentTitle ?? "Library")").font(.caption)
                                    ProgressView(value: Double(updater.completedCount),
                                                 total: Double(max(updater.totalCount, 1)))
                                }
                            }
                            if !isSelecting && !hasFilters && selectedCategory == nil && search.isEmpty && !continueReading.isEmpty {
                                shelf
                            }
                            if !shownCategories.isEmpty { categoryBar }
                            grid
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                }
            }
    }

    @ViewBuilder private var privacyButton: some View {
        if categories.contains(where: \.isPrivate) {
            Button {
                if lock.isUnlocked { lock.lock() } else { Task { await lock.unlock() } }
            } label: {
                Image(systemName: lock.isUnlocked ? "lock.open" : "lock")
            }
            .accessibilityLabel(lock.isUnlocked ? "Hide private categories" : "Show private categories")
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortRaw) {
                ForEach(LibrarySort.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Picker("Reading status", selection: $readingFilterRaw) {
                ForEach(LibraryReadingFilter.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Toggle("Unread only", systemImage: "circle.fill", isOn: $unreadOnly)
            Toggle("Available offline", systemImage: "arrow.down.circle", isOn: $offlineOnly)
            if hasFilters {
                Button("Clear filters") {
                    unreadOnly = false; offlineOnly = false
                    readingFilterRaw = LibraryReadingFilter.all.rawValue
                }
            }
        } label: {
            Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill"
                                         : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Sort and filter")
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(shownCategories) { category in
                    chip(category.name, selected: selectedCategory == category.id) {
                        selectedCategory = category.id
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Theme.accent : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continue reading").font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(continueReading) { manga in
                        NavigationLink(value: manga) {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverView(data: manga.coverData, title: manga.title)
                                    .frame(width: 110)
                                Text(manga.title).font(.caption.weight(.medium)).lineLimit(1)
                                    .frame(width: 110, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 10) {
            if visible.isEmpty {
                ContentUnavailableView(hasFilters ? "No matching titles" : "No results",
                                       systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(visible) { manga in
                        if isSelecting {
                            Button {
                                if selected.contains(manga.id) { selected.remove(manga.id) }
                                else { selected.insert(manga.id) }
                            } label: {
                                MangaCell(manga: manga)
                                    .overlay(alignment: .topLeading) {
                                        Image(systemName: selected.contains(manga.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title2).foregroundStyle(.white, Theme.accent)
                                            .padding(8).background(.ultraThinMaterial, in: Circle())
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(manga.title)
                            .accessibilityValue(selected.contains(manga.id) ? "Selected" : "Not selected")
                            .accessibilityIdentifier("select-" + manga.title)
                        } else {
                        NavigationLink(value: manga) { MangaCell(manga: manga) }
                            .accessibilityIdentifier("manga-" + manga.title)
                            .buttonStyle(.plain)
                            .contextMenu {
                                Menu("Move to category", systemImage: "folder") {
                                    Button("None") { manga.categoryID = nil }
                                    ForEach(categories) { category in
                                        Button(category.name) { manga.categoryID = category.id }
                                    }
                                }
                                Button(manga.mergeGroupID == nil ? "Delete" : "Delete this edition", systemImage: "trash", role: .destructive) {
                                    delete(manga)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Text("\(selected.count) selected").font(.subheadline.monospacedDigit())
                .accessibilityIdentifier("librarySelectionCount")
            Spacer()
            Button("Select all") { selected = Set(visible.map(\.id)) }
                .disabled(visible.isEmpty)
            Menu("Move", systemImage: "folder") {
                Button("None") { moveSelected(to: nil) }
                ForEach(categories) { category in
                    Button(category.name) { moveSelected(to: category.id) }
                }
            }
            .disabled(selected.isEmpty)
        }
        .padding().background(.regularMaterial)
    }

    private func moveSelected(to categoryID: UUID?) {
        let titles = library.filter { selected.contains($0.id) }
        do {
            try LibraryOperations.move(titles, to: categoryID, context: context)
            selected.removeAll()
            isSelecting = false
        } catch { errorMessage = "Couldn't move titles: \(error.localizedDescription)" }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error): errorMessage = error.localizedDescription
        case .success(let urls):
            Task {
                for url in urls {
                    do { try await LibraryImporter.importFile(at: url, into: nil, context: context) }
                    catch { errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)" }
                }
            }
        }
    }

    private func delete(_ manga: Manga) {
        let chapters = manga.chapters
        let files = chapters.map { $0.isRemote ? $0.downloadDirectory : $0.fileURL }
        Task {
            await DownloadManager.shared.cancelAndWait(Set(chapters.map(\.id)))
            context.delete(manga)
            do {
                try context.save()
                for url in files { try? FileManager.default.removeItem(at: url) }
            } catch { errorMessage = "Couldn't delete the series: \(error.localizedDescription)" }
        }
    }
}

private struct MangaCell: View {
    let manga: Manga

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverView(data: manga.coverData, title: manga.title)
                .overlay(alignment: .topTrailing) {
                    if manga.unreadCount > 0 {
                        Text("\(manga.unreadCount)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.accent, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if manga.progress > 0 && manga.progress < 1 {
                        ProgressView(value: manga.progress)
                            .tint(Theme.accent)
                            .padding(6)
                            .background(.ultraThinMaterial)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(manga.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                if manga.mergeGroupID != nil {
                    Label("Edition group", systemImage: "square.stack")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String {
        let count = manga.chapters.count
        if count == 0 { return "No chapters" }
        if manga.unreadCount == 0 { return "Completed" }
        return "\(manga.unreadCount) unread · \(count) ch."
    }
}
