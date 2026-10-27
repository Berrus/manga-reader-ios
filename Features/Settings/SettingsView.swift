import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @Environment(SourceStore.self) private var store
    @Environment(\.modelContext) private var context
    @State private var showSourceInstaller = false
    @State private var exportDocument = BackupDocument(data: Data())
    @State private var showExporter = false
    @State private var showRestorer = false
    @State private var message: String?
    @State private var connecting = false

    var body: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
                .fileExporter(isPresented: $showExporter, document: exportDocument,
                              contentType: .json, defaultFilename: "FolioReader-backup") { result in
                    if case .failure(let error) = result { message = error.localizedDescription }
                }
                .fileImporter(isPresented: $showRestorer, allowedContentTypes: [.json],
                              onCompletion: restoreBackup)
                .sheet(isPresented: $showSourceInstaller) { SourceInstallerView() }
                .alert("Folio Reader", isPresented: Binding(
                    get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("OK") { message = nil }
                } message: { Text(message ?? "") }
                .onChange(of: store.enabled) { _, _ in store.persistEnabled() }
        }
    }

    private var settingsForm: some View {
        Form {
            librarySection
            backupSection
            if UIApplication.shared.supportsAlternateIcons {
                Section("App icon") { AppIconPicker() }
            }
            trackingSection
            if DistributionPolicy.allowsCustomSources {
                customSourceSection
                if store.enabled { installedSourcesSection }
            }
        }
    }
    private var librarySection: some View {
        Section("Library") {
            NavigationLink("Appearance") { AppearanceSettingsView() }
            NavigationLink("Reader") { ReaderPreferencesView() }
            NavigationLink("Categories") { CategoriesView() }
            NavigationLink("Servers") { ServersView() }
            NavigationLink("Notifications") { NotificationSettingsView() }
            NavigationLink("Updates") { UpdatesView() }
            NavigationLink("Downloads") { DownloadsSettingsView() }
        }
    }
    private var backupSection: some View {
        Section {
            Button("Export backup…", systemImage: "square.and.arrow.up", action: exportBackup)
            Button("Restore backup…", systemImage: "square.and.arrow.down") { showRestorer = true }
        } header: { Text("Backup") }
        footer: { Text("Backs up metadata, not comic files. Restore uses book identities and skips ambiguous title matches.") }
    }
    private var trackingSection: some View {
        Section {
            if !AniListAuth.shared.hasClientID {
                Text("Configure your AniList client ID to enable tracking.").font(.footnote)
            } else if AniListAuth.shared.isConnected {
                Button("Disconnect AniList", role: .destructive) { AniListAuth.shared.disconnect() }
            } else {
                Button(connecting ? "Connecting…" : "Connect AniList", action: connectAniList)
                    .disabled(connecting)
            }
        } header: { Text("Tracking") }
        footer: { Text("Reading progress is sent to AniList after you finish a chapter.") }
    }
    private var customSourceSection: some View {
        Section {
            Toggle("Enable custom sources", isOn: Binding(get: { store.enabled }, set: { store.enabled = $0 }))
            if let migration = store.migrationMessage { Text(migration).font(.footnote) }
        } header: { Text("Advanced") }
        footer: { Text("Custom sources contain declarative JSON, not executable programs. All endpoints and images must use their declared HTTPS domains.") }
    }
    private var installedSourcesSection: some View {
        Section("Installed sources") {
            ForEach(store.manifests) { manifest in
                VStack(alignment: .leading) {
                    Text(manifest.name)
                    Text(manifest.hosts.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }.swipeActions {
                    Button("Remove", role: .destructive) { store.remove(manifest) }
                }
            }
            Button("Add source…", systemImage: "plus") { showSourceInstaller = true }
        }
    }
    private func exportBackup() {
        do {
            exportDocument = BackupDocument(data: try BackupService.encode(BackupService.snapshot(context: context)))
            showExporter = true
        } catch { message = error.localizedDescription }
    }
    private func restoreBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 10_000_001) ?? Data()
            guard data.count <= 10_000_000 else { throw TransportError.tooLarge }
            let summary = try BackupService.restore(BackupService.decode(data), into: context)
            message = "Restored \(summary.series) series and \(summary.chapters) chapters. Skipped \(summary.ambiguous) ambiguous series."
        } catch { message = "Couldn't restore: \(error.localizedDescription)" }
    }
    private func connectAniList() {
        connecting = true
        Task {
            defer { connecting = false }
            do { try await AniListAuth.shared.connect() }
            catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {}
            catch { message = error.localizedDescription }
        }
    }
}

private struct SourceInstallerView: View {
    @Environment(SourceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var pending: JSSourceManifest?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("https://…/source.json", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(busy ? "Loading…" : "Review source", action: fetch).disabled(busy)
                if let pending {
                    Section("Install \(pending.name)?") {
                        Text("Allowed domains: " + pending.hosts.joined(separator: ", "))
                        Button("Install") {
                            do { try store.add(pending); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Add source")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    private func fetch() {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Enter a valid HTTPS address."; return
        }
        busy = true; error = nil; pending = nil
        Task {
            defer { busy = false }
            do { pending = try await store.fetchManifest(from: url) }
            catch { self.error = error.localizedDescription }
        }
    }
}
