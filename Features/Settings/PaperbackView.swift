#if !APP_STORE
import SwiftUI

/// Add a Paperback 0.9 repository by its base address, then install extensions from it.
struct PaperbackView: View {
    @Bindable private var store = PaperbackStore.shared
    @State private var address = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("Enable Paperback extensions", isOn: $store.enabled)
                    .onChange(of: store.enabled) { _, _ in store.persistEnabled() }
            } footer: {
                Text("Extensions are third-party JavaScript. They can contact any public HTTPS website to load comics, but cannot read your files, library or accounts. Install only repositories you trust. Settings screens, login and discover pages of extensions are not supported. No repositories are included.")
            }
            Section("Installed") {
                if store.installed.isEmpty { Text("None installed").foregroundStyle(.secondary) }
                ForEach(store.installed) { info in
                    VStack(alignment: .leading) {
                        Text(info.name)
                        Text("Version \(info.version)").font(.caption).foregroundStyle(.secondary)
                    }.swipeActions { Button("Remove", role: .destructive) { store.remove(info) } }
                }
            }
            if store.enabled {
                Section("Repositories") {
                    ForEach(store.repositories, id: \.self) { base in
                        NavigationLink(base) { PaperbackRepositoryView(base: base) }
                            .swipeActions { Button("Remove", role: .destructive) { store.removeRepository(base) } }
                    }
                    TextField("https://example.github.io/extensions/0.9/stable", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("Add repository", systemImage: "plus") {
                        do { try store.addRepository(address); address = ""; message = nil }
                        catch { message = error.localizedDescription }
                    }.disabled(address.isEmpty)
                }
            }
            if let message { Section { Text(message).font(.footnote) } }
        }
        .navigationTitle("Paperback extensions")
    }
}

struct PaperbackRepositoryView: View {
    let base: String
    @Bindable private var store = PaperbackStore.shared
    @State private var items: [PaperbackExtensionInfo] = []
    @State private var loading = true
    @State private var busy: String?
    @State private var message: String?

    var body: some View {
        List {
            if loading { ProgressView() }
            ForEach(items) { info in
                HStack {
                    VStack(alignment: .leading) {
                        Text(info.name)
                        Text(detail(info)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(label(info)) { install(info) }
                        .buttonStyle(.bordered).disabled(busy != nil)
                }
            }
            if let message { Text(message).font(.footnote) }
        }
        .navigationTitle("Extensions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { items = try await store.index(of: base); message = items.isEmpty ? "This repository lists no extensions." : nil }
            catch { message = error.localizedDescription }
            loading = false
        }
    }

    private func detail(_ info: PaperbackExtensionInfo) -> String {
        [info.version, info.language, info.contentRating?.capitalized].compactMap { $0 }.joined(separator: " · ")
    }
    private func label(_ info: PaperbackExtensionInfo) -> String {
        guard let current = store.installed.first(where: { $0.id == info.id }) else { return busy == info.id ? "…" : "Install" }
        return current.version == info.version ? "Reinstall" : "Update"
    }
    private func install(_ info: PaperbackExtensionInfo) {
        busy = info.id; message = nil
        Task {
            defer { busy = nil }
            do { try await store.install(info, from: base); message = "Installed \(info.name)." }
            catch { message = error.localizedDescription }
        }
    }
}
#endif
