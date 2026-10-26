import SwiftUI
import SwiftData

@main
struct MangaReaderApp: App {
    private let container: ModelContainer

    init() {
        do {
            let schema = Schema([Manga.self, Chapter.self])
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
                BrowseView()
                    .tabItem { Label("Browse", systemImage: "globe") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .environment(SourceStore.shared)
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
