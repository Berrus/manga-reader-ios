import SwiftUI

/// Lists the sources (extensions) installed on one Suwayomi server.
struct SuwayomiSourcesView: View {
    let server: ServerConfig
    @State private var sources: [SuwayomiSourceInfo] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var error: String?

    private var filtered: [SuwayomiSourceInfo] {
        query.isEmpty ? sources : sources.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) || $0.lang.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(filtered) { info in
            if let source = ServerStore.shared.suwayomiSource(serverID: server.id, sourceID: info.id,
                                                              name: info.displayName) {
                NavigationLink {
                    SourceSearchView(source: source)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.displayName)
                        if !info.lang.isEmpty {
                            Text(info.lang.uppercased()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if let error {
                ContentUnavailableView("Couldn't load sources", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else if sources.isEmpty {
                ContentUnavailableView("No sources on this server", systemImage: "tray",
                    description: Text("Install extensions in the Suwayomi web interface, then pull to refresh."))
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search sources")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let client = ServerStore.shared.suwayomiClient(for: server) else {
            error = "Check this server's address in Settings."
            isLoading = false
            return
        }
        error = nil
        defer { isLoading = false }
        do { sources = try await client.sources() }
        catch { sources = []; self.error = error.localizedDescription }
    }
}
