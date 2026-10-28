import SwiftUI

/// One place for "what's new": chapters found for your library, and the feed of your saved searches.
struct UpdatesTab: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case library = "My library", saved = "Saved searches"
        var id: Self { self }
    }
    @State private var mode = Mode.library

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 8)
                switch mode {
                case .library: UpdatesView()
                case .saved: FeedView()
                }
            }
            .navigationTitle("Updates")
        }
    }
}
