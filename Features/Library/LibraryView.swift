import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, title, unread
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: return "Recently added"
        case .title: return "Title"
        case .unread: return "Unread"
        }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Manga.addedAt, order: .reverse) private var library: [Manga]
    @AppStorage("librarySort") private var sortRaw = LibrarySort.recent.rawValue
    @AppStorage("libraryUnreadOnly") private var unreadOnly = false
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var search = ""

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 18, alignment: .top)]

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recent }

    private var visible: [Manga] {
        var items = library
        if !search.isEmpty { items = items.filter { $0.title.localizedCaseInsensitiveContains(search) } }
        if unreadOnly { items = items.filter { $0.unreadCount > 0 } }
        switch sort {
        case .recent: break
        case .title: items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .unread: items.sort { $0.unreadCount > $1.unreadCount }
        }
        return items
    }

    private var continueReading: [Manga] {
        library.filter { $0.chapters.contains { $0.inProgress } }
    }

    var body: some View {
        NavigationStack {
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
                            if search.isEmpty && !continueReading.isEmpty {
                                shelf
                            }
                            grid
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $search, prompt: "Search library")
            .navigationDestination(for: Manga.self) { MangaDetailView(manga: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { sortMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import", systemImage: "plus") { showImporter = true }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: UTType.comicArchives,
                          allowsMultipleSelection: true) { result in
                handleImport(result)
            }
            .alert("Import failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortRaw) {
                ForEach(LibrarySort.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Toggle("Unread only", systemImage: "circle.fill", isOn: $unreadOnly)
        } label: {
            Image(systemName: unreadOnly ? "line.3.horizontal.decrease.circle.fill"
                                         : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Sort and filter")
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
                ContentUnavailableView(unreadOnly ? "Nothing unread" : "No results",
                                       systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(visible) { manga in
                        NavigationLink(value: manga) { MangaCell(manga: manga) }
                            .accessibilityIdentifier("manga-" + manga.title)
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    delete(manga)
                                }
                            }
                    }
                }
            }
        }
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
        LibraryImporter.deleteFiles(for: manga)
        context.delete(manga)
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
