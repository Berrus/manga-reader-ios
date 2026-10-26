import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @Environment(SourceStore.self) private var store
    @State private var showAdd = false
    @State private var address = ""
    @State private var pending: JSSourceManifest?
    @State private var errorMessage: String?
    @State private var isFetching = false
    @Environment(\.modelContext) private var context
    @State private var exportDocument = BackupDocument(data: Data())
    @State private var showExporter = false
    @State private var showRestorer = false
    @State private var infoMessage: String?

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Library") {
                    NavigationLink("Categories") { CategoriesView() }
                    NavigationLink("Servers") { ServersView() }
                }

                Section {
                    Button("Export backup…", systemImage: "square.and.arrow.up") { exportBackup() }
                    Button("Restore backup…", systemImage: "square.and.arrow.down") { showRestorer = true }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Saves categories, reading progress and tracker links (not the comic files). Restore after re-importing your files; series are matched by title.")
                }

                if UIApplication.shared.supportsAlternateIcons {
                    Section("App icon") { AppIconPicker() }
                }

                Section {
                    if !AniListAuth.shared.hasClientID {
                        Text("Add your AniList client ID in project.yml to enable tracking (see README).")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if AniListAuth.shared.isConnected {
                        Button("Disconnect AniList", role: .destructive) { AniListAuth.shared.disconnect() }
                    } else {
                        Button("Connect AniList") { connectAniList() }
                    }
                } header: {
                    Text("Tracking")
                } footer: {
                    Text("Reading progress is sent to AniList after you finish a chapter. Progress only moves forward.")
                }

                Section {
                    Toggle("Enable custom sources", isOn: $store.enabled)
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Custom sources are small programs written by third parties. They run in a sandbox with no file access and can only contact the websites they declare. This app hosts no content and includes no sources. You are responsible for the sources you add.")
                }

                if store.enabled {
                    Section("Installed sources") {
                        ForEach(store.manifests) { manifest in
                            VStack(alignment: .leading) {
                                Text(manifest.name)
                                Text("v\(manifest.version) · \(manifest.hosts.joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    store.remove(manifest)
                                }
                            }
                        }
                        Button("Add source…", systemImage: "plus") { showAdd = true }
                    } footer: {
                        Text("To report content, remove the source here and contact its author.")
                    }
                }
            }
            .navigationTitle("Settings")
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                          defaultFilename: "FolioReader-backup") { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .fileImporter(isPresented: $showRestorer, allowedContentTypes: [.json]) { result in
                restoreBackup(result)
            }
            .alert("Backup", isPresented: Binding(get: { infoMessage != nil },
                                                  set: { if !$0 { infoMessage = nil } })) {
                Button("OK") { infoMessage = nil }
            } message: { Text(infoMessage ?? "") }
            .onChange(of: store.enabled) { _, _ in store.persistEnabled() }
            .alert("Add source", isPresented: $showAdd) {
                TextField("https://…", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { address = "" }
                Button("Continue") { fetch() }
            } message: {
                Text("Enter the address of a source definition (JSON).")
            }
            .alert("Install \(pending?.name ?? "source")?",
                   isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                Button("Cancel", role: .cancel) { pending = nil }
                Button("Install") { install() }
            } message: {
                if let pending {
                    Text("This source runs code from its author and can contact: \(pending.hosts.joined(separator: ", ")). Only install sources you trust.")
                }
            }
            .alert("Couldn't add source", isPresented: Binding(get: { errorMessage != nil },
                                                               set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .overlay { if isFetching { ProgressView() } }
        }
    }

    private func exportBackup() {
        do {
            exportDocument = BackupDocument(data: try BackupService.encode(try BackupService.snapshot(context: context)))
            showExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let file = try BackupService.decode(try Data(contentsOf: url))
            let summary = try BackupService.restore(file, into: context)
            infoMessage = "Restored \(summary.series) series, \(summary.chapters) chapters updated, \(summary.categories) new categories, \(summary.links) tracker links."
        } catch {
            errorMessage = "Couldn't restore: \(error.localizedDescription)"
        }
    }

    private func connectAniList() {
        Task {
            do { try await AniListAuth.shared.connect() }
            catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func fetch() {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "That isn't a valid address."
            return
        }
        address = ""
        isFetching = true
        Task {
            defer { isFetching = false }
            do { pending = try await store.fetchManifest(from: url) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func install() {
        guard let manifest = pending else { return }
        pending = nil
        do { try store.add(manifest) }
        catch { errorMessage = error.localizedDescription }
    }
}
