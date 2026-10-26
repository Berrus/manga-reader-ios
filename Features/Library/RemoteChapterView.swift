import SwiftUI

/// Streams a chapter of a remote series that hasn't been downloaded. Reading progress is only
/// tracked for downloaded chapters.
struct RemoteChapterView: View {
    let chapter: Chapter

    var body: some View {
        if let sourceID = chapter.manga?.sourceID, let remoteID = chapter.remoteID,
           let source = SourceRegistry.source(id: sourceID) {
            RemoteReaderView(source: source,
                             chapter: ChapterSummary(id: remoteID, name: chapter.name, number: chapter.number))
        } else {
            ContentUnavailableView("Source unavailable", systemImage: "network.slash",
                description: Text("Check your servers and sources in Settings, or download the chapter while online."))
        }
    }
}
