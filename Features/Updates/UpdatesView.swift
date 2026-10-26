import SwiftUI
import SwiftData

struct UpdatesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Manga> { $0.lastUpdatedAt != nil },
           sort: \Manga.lastUpdatedAt, order: .reverse) private var updated: [Manga]
    @State private var updater = LibraryUpdater.shared
    private var days: [Date] {
        Array(Set(updated.compactMap { $0.lastUpdatedAt.map { Calendar.current.startOfDay(for: $0) } })).sorted(by: >)
    }
    var body: some View {
        List {
            if updater.isRunning {
                Section {
                    ProgressView(value: Double(updater.completedCount), total: Double(max(updater.totalCount, 1)))
                    Text(updater.currentTitle ?? "Checking library…").font(.caption)
                }
            }
            if !updater.lastErrors.isEmpty {
                Section("Last check issues") {
                    ForEach(updater.lastErrors) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.title).font(.headline)
                            Text(issue.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if updated.isEmpty && !updater.isRunning {
                ContentUnavailableView("No updates yet", systemImage: "arrow.triangle.2.circlepath",
                    description: Text("New chapters found for your library will appear here."))
            }
            ForEach(days, id: \.self) { day in
                Section(day.formatted(date: .abbreviated, time: .omitted)) {
                    ForEach(updated.filter {
                        $0.lastUpdatedAt.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
                    }) { manga in
                        NavigationLink {
                            MangaDetailView(manga: manga)
                        } label: {
                            HStack {
                                CoverView(data: manga.coverData, title: manga.title).frame(width: 40)
                                VStack(alignment: .leading) {
                                    Text(manga.title)
                                    Text("\(manga.unreadCount) unread chapters")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Updates")
        .toolbar {
            Button("Check now", systemImage: "arrow.clockwise") {
                Task { await updater.runIfNeeded(context: context, force: true) }
            }.disabled(updater.isRunning)
        }
        .refreshable { await updater.runIfNeeded(context: context, force: true) }
    }
}
