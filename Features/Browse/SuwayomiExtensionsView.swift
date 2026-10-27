import SwiftUI

/// Manage the extension repositories and extensions on one Suwayomi server. Everything here runs on
/// the user's server; the app only sends the requests.
struct SuwayomiExtensionsView: View {
    let server: ServerConfig

    /// The community repository documented at keiyoushi.github.io. Offered as a convenience only in builds
    /// that allow public sources; the App Store build has no extension management at all.
    static let keiyoushiRepository = "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json"

    @State private var repositories: [String] = []
    @State private var extensions: [SuwayomiExtension] = []
    @State private var newRepository = ""
    @State private var pendingRepository: String?
    @State private var search = ""
    @State private var isLoading = true
    @State private var busyPackage: String?
    @State private var message: String?

    private var client: SuwayomiClient? { ServerStore.shared.suwayomiClient(for: server) }

    private var shown: [SuwayomiExtension] {
        search.isEmpty ? extensions : extensions.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.lang.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(repositories, id: \.self) { repository in
                    Text(repository).font(.footnote).lineLimit(2)
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) { remove(repository) }
                        }
                }
                HStack {
                    TextField("https://…/index.min.json", text: $newRepository)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("Add") { ask(newRepository) }.disabled(newRepository.isEmpty)
                }
                if !repositories.contains(Self.keiyoushiRepository) {
                    Button("Use the Keiyoushi repository", systemImage: "plus") { ask(Self.keiyoushiRepository) }
                }
            } header: {
                Text("Repositories on \(server.name)")
            } footer: {
                Text("Extensions are Android packages that run on your Suwayomi server, not on this device. Folio Reader doesn't host, provide or vouch for any repository or extension; adding one is your choice.")
            }

            if let message { Section { Text(message).font(.footnote) } }

            Section("Extensions") {
                if isLoading { ProgressView() }
                else if extensions.isEmpty { Text(repositories.isEmpty ? "Add a repository first." : "No extensions found.").foregroundStyle(.secondary) }
                ForEach(shown) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text("\(item.lang.uppercased()) · v\(item.versionName)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if busyPackage == item.pkgName { ProgressView() }
                        else { actionButtons(for: item) }
                    }
                }
            }
        }
        .navigationTitle("Extensions")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search extensions")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Add this repository to \(server.name)?", isPresented: Binding(
            get: { pendingRepository != nil }, set: { if !$0 { pendingRepository = nil } }), titleVisibility: .visible) {
            if let pendingRepository {
                Button("Add repository") { add(pendingRepository) }
            }
            Button("Cancel", role: .cancel) { pendingRepository = nil }
        } message: {
            Text("\(pendingRepository ?? "")\n\nExtensions from it will be able to run on your server.")
        }
    }

    @ViewBuilder private func actionButtons(for item: SuwayomiExtension) -> some View {
        if item.isInstalled {
            if item.hasUpdate { Button("Update") { perform(.update, item) }.buttonStyle(.borderedProminent) }
            Button("Remove", role: .destructive) { perform(.uninstall, item) }.buttonStyle(.bordered)
        } else {
            Button("Install") { perform(.install, item) }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: Actions

    private func load() async {
        guard let client else { message = "Check this server's address in Settings."; isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        do {
            repositories = try await client.extensionRepositories()
            extensions = repositories.isEmpty ? [] : try await client.fetchExtensions()
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func ask(_ text: String) {
        guard let valid = SuwayomiClient.normalizedRepository(text, existing: repositories) else {
            message = "Enter a new https:// address without a username or password (at most 20 repositories)."
            return
        }
        pendingRepository = valid
    }

    private func add(_ repository: String) {
        pendingRepository = nil
        newRepository = ""
        Task { await save(repositories + [repository]) }
    }

    private func remove(_ repository: String) {
        Task { await save(repositories.filter { $0 != repository }) }
    }

    private func save(_ list: [String]) async {
        guard let client else { return }
        do {
            try await client.setExtensionRepositories(list)
            await load()
        } catch { message = error.localizedDescription }
    }

    private func perform(_ action: SuwayomiExtensionAction, _ item: SuwayomiExtension) {
        guard let client, busyPackage == nil else { return }
        busyPackage = item.pkgName
        Task {
            defer { busyPackage = nil }
            do {
                try await client.apply(action, to: item.pkgName)
                extensions = try await client.fetchExtensions()
                message = nil
            } catch { message = error.localizedDescription }
        }
    }
}
