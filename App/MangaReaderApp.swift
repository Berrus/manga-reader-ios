import SwiftUI
import SwiftData

@main
struct MangaReaderApp: App {
    private let container: ModelContainer

    init() {
        do {
            let schema = Schema([Manga.self, Chapter.self, TrackLink.self, Category.self])
            #if DEBUG
            let inMemory = ProcessInfo.processInfo.environment["UI_TESTING"] == "1"
            #else
            let inMemory = false
            #endif
            container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
            ])
        } catch {
            fatalError("Could not open the library: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                LibraryView()
                    .tabItem { Label("Library", systemImage: "books.vertical") }
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock") }
                BrowseView()
                    .tabItem { Label("Browse", systemImage: "globe") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .environment(SourceStore.shared)
            .tint(Theme.accent)
            .task {
                AniListAuth.shared.restore()
                await TrackerSync.shared.syncAll(context: container.mainContext)
            }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.environment["UI_TESTING"] == "1" {
                    do { try await DemoLibrary.seed(context: container.mainContext) }
                    catch { assertionFailure("Demo import failed: \(error)") }
                }
                #endif
            }
        }
        .modelContainer(container)
    }
}
