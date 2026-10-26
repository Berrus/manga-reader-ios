import SwiftUI
import SwiftData

@main
struct MangaReaderApp: App {
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
        }
        .modelContainer(for: [Manga.self, Chapter.self])
    }
}
