import SwiftUI

struct SettingsView: View {
    @Environment(SourceStore.self) private var store
    @State private var showAdd = false
    @State private var address = ""
    @State private var pending: JSSourceManifest?
    @State private var errorMessage: String?
    @State private var isFetching = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                if UIApplication.shared.supportsAlternateIcons {
                    Section("App icon") { AppIconPicker() }
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
