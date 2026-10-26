import SwiftUI

import SwiftData

@main

struct MangaReaderApp: App {

    var body: some Scene {

        WindowGroup { LibraryView() }

            .modelContainer(for: [Manga.self, Chapter.self])

    }

}

