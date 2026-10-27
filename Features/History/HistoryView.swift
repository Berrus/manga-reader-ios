import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(filter: #Predicate<Manga> { $0.lastReadAt != nil },
           sort: \Manga.lastReadAt, order: .reverse)
    private var allHistory: [Manga]
    @Query private var categories: [Category]
    private var history: [Manga] {
        PrivacyFilter.visible(allHistory, categories: categories, unlocked: PrivacyLock.shared.isUnlocked)
    }

    var body: some View {
        NavigationStack {
            Group {
                if history.isEmpty {
                    ContentUnavailableView("No history yet", systemImage: "clock",
                        description: Text("Series you read will appear here."))
                } else {
                    List {
                        ForEach(history) { manga in
                            NavigationLink(value: manga) { row(manga) }
                                .swipeActions {
                                    Button("Remove", systemImage: "xmark", role: .destructive) {
                                        manga.lastReadAt = nil
                                        manga.lastReadChapterName = nil
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Manga.self) { MangaDetailView(manga: $0) }
        }
    }

    private func row(_ manga: Manga) -> some View {
        HStack(spacing: 12) {
            CoverView(data: manga.coverData, title: manga.title).frame(width: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(manga.title).font(.headline).lineLimit(2)
                if let name = manga.lastReadChapterName {
                    Text(name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let date = manga.lastReadAt {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if manga.progress > 0 { ProgressRing(progress: manga.progress).frame(width: 22, height: 22) }
        }
    }
}
