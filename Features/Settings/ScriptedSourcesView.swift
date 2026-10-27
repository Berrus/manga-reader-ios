#if !APP_STORE
import SwiftUI

/// Opt-in JavaScript sources. Not compiled into the App Store configuration.
struct ScriptedSourcesView: View {
    @Bindable private var store = ScriptedSourceStore.shared
    @State private var address = ""
    @State private var pending: ScriptedSourceManifest?
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enable scripted sources", isOn: $store.enabled)
                    .onChange(of: store.enabled) { _, _ in store.persistEnabled() }
            } footer: {
                Text("Scripted sources run third-party JavaScript. A script can only contact the domains it declares over HTTPS, cannot read your files, library or accounts, and must match the checksum in its listing. Install only sources you trust. No sources are included.")
            }
            Section("Installed") {
                if store.manifests.isEmpty { Text("None installed").foregroundStyle(.secondary) }
                ForEach(store.manifests) { manifest in
                    VStack(alignment: .leading) {
                        Text(manifest.name)
                        Text("Version \(manifest.version) · \(manifest.hosts.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary)
                    }.swipeActions { Button("Remove", role: .destructive) { store.remove(manifest) } }
                }
            }
            if store.enabled {
                Section("Add a source") {
                    TextField("https://example.com/source.json", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button(busy ? "Checking…" : "Review source") { review() }
                        .disabled(busy || address.isEmpty)
                }
            }
            if let message { Section { Text(message).font(.footnote) } }
        }
        .navigationTitle("Scripted sources")
        .confirmationDialog(pending.map { "Install \($0.name)?" } ?? "", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button(pending.flatMap { store.replacementWarning(for: $0) } == nil ? "Install" : "Replace source") { install() }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            if let pending {
                Text("Version \(pending.version). It runs JavaScript and may contact: \(pending.hosts.joined(separator: ", ")). \(store.replacementWarning(for: pending) ?? "")")
            }
        }
    }

    private func review() {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            message = "That is not a valid address."; return
        }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do { pending = try await store.fetchManifest(from: url) }
            catch { message = error.localizedDescription }
        }
    }
    private func install() {
        guard let manifest = pending else { return }
        pending = nil; busy = true
        Task {
            defer { busy = false }
            do { try await store.install(manifest); message = "Installed \(manifest.name)."; address = "" }
            catch { message = error.localizedDescription }
        }
    }
}
#endif
