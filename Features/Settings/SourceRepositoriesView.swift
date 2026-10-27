import SwiftUI

/// A repository is a JSON object containing a version and complete Folio source definitions.
struct SourceRepositoryIndex: Decodable {
    let version: Int
    let sources: [JSSourceManifest]

    static func decode(_ data: Data) throws -> SourceRepositoryIndex {
        let index = try JSONDecoder().decode(SourceRepositoryIndex.self, from: data)
        guard index.version == 1, index.sources.count <= 200,
              Set(index.sources.map(\.id)).count == index.sources.count else {
            throw JSSourceError.invalidManifest("Unsupported repository, too many sources, or duplicate IDs.")
        }
        for source in index.sources { try SourceStore.validate(source) }
        return index
    }
}

struct SourceRepositoriesView: View {
    @Environment(SourceStore.self) private var store
    @AppStorage("sourceRepositories") private var storedRepositories = "[]"
    @State private var address = ""
    @State private var selectedAddress: String?
    @State private var sources: [JSSourceManifest] = []
    @State private var search = ""
    @State private var busy = false
    @State private var message: String?
    @State private var pending: JSSourceManifest?

    private var addresses: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(storedRepositories.utf8))) ?? []
    }

    var body: some View {
        List {
            Section("Add repository") {
                TextField("https://example.com/repository.json", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Add and load", action: addRepository).disabled(busy)
            }
            Section("Repositories") {
                ForEach(addresses, id: \.self) { item in
                    Button(item) { load(item) }.disabled(busy)
                        .swipeActions {
                            Button("Remove", role: .destructive) { remove(item) }
                        }
                }
                if let selectedAddress {
                    Button(busy ? "Refreshing…" : "Refresh selected repository") { load(selectedAddress) }
                        .disabled(busy)
                }
            }
            if selectedAddress != nil {
                Section("Sources") {
                    TextField("Search sources", text: $search)
                    ForEach(sources.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { source in
                        Button {
                            pending = source
                        } label: {
                            VStack(alignment: .leading) {
                                Text(source.name)
                                Text("Version \(source.version) · " +
                                     (store.manifests.contains { $0.id == source.id } ? "Installed" : "Available"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if let message { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Source repositories")
        .confirmationDialog("Install this source?", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let pending {
                let replacing = store.replacementWarning(for: pending, origin: selectedAddress) != nil
                Button(replacing ? "Replace source" : "Install or update", role: replacing ? .destructive : nil) {
                    do { try store.add(pending, origin: selectedAddress, allowReplacement: replacing); message = "\(pending.name) installed." }
                    catch { message = error.localizedDescription }
                    self.pending = nil
                }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            if let pending {
                Text(store.replacementWarning(for: pending, origin: selectedAddress)
                     ?? "\(pending.name) · Allowed domains: \(pending.hosts.joined(separator: ", "))")
            }
        }
    }

    private func addRepository() {
        let candidate = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: candidate), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, candidate.count <= 2048 else {
            message = "Enter an HTTPS repository URL without credentials."; return
        }
        guard addresses.contains(candidate) || addresses.count < 20 else {
            message = "The maximum is 20 repositories."; return
        }
        load(candidate, saveOnSuccess: true)
    }

    private func remove(_ item: String) {
        save(addresses.filter { $0 != item })
        if selectedAddress == item { selectedAddress = nil; sources = [] }
    }

    private func save(_ items: [String]) {
        guard let data = try? JSONEncoder().encode(items), let text = String(data: data, encoding: .utf8) else { return }
        storedRepositories = text
    }

    private func load(_ item: String, saveOnSuccess: Bool = false) {
        guard let url = URL(string: item), let host = url.host, url.scheme == "https" else {
            message = "Invalid repository URL."; return
        }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let (data, _) = try await SourceTransport.load(URLRequest(url: url),
                    policy: SourceAccessPolicy(hosts: [host]), maxBytes: 1_000_000)
                let index = try SourceRepositoryIndex.decode(data)
                if saveOnSuccess && !addresses.contains(item) { save(addresses + [item]) }
                selectedAddress = item
                sources = index.sources.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                address = ""
                message = "Loaded \(sources.count) sources."
            } catch {
                message = "Couldn't load this Folio repository: \(error.localizedDescription)"
            }
        }
    }
}
