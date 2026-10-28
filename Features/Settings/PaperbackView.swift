#if !APP_STORE
import SwiftUI

/// Add a Paperback 0.9 repository by its base address, then install extensions from it.
struct PaperbackView: View {
    @Bindable private var store = PaperbackStore.shared
    @State private var address = ""
    @State private var message: String?
    @State private var showExplanation = false
    @State private var pendingRemoval: PaperbackExtensionInfo?
    @State private var search = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable Paperback extensions", isOn: $store.enabled)
                    .onChange(of: store.enabled) { _, _ in store.persistEnabled() }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Extensions run third-party JavaScript and can contact public HTTPS sites. Install only repositories you trust.")
                    Button(showExplanation ? "Show less" : "Learn more") { showExplanation.toggle() }
                    if showExplanation {
                        Text("Extensions cannot read your files, library or accounts. Extension settings and login are not supported. Discovery support varies by extension. No repositories are included.")
                    }
                }
            }
            Section("Installed") {
                if store.installed.isEmpty { Text("None installed").foregroundStyle(.secondary) }
                ForEach(store.installed.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { info in
                    Toggle(isOn: Binding(
                        get: { store.isEnabled(info) },
                        set: { store.setEnabled($0, for: info) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(info.name)
                            Text("Version \(info.version)").font(.caption).foregroundStyle(.secondary)
                        }
                    }.swipeActions { Button("Remove", role: .destructive) { pendingRemoval = info } }
                }
            }
            if store.enabled {
                Section("Repositories") {
                    ForEach(store.repositories, id: \.self) { base in
                        NavigationLink {
                            PaperbackRepositoryView(base: base)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(URL(string: base)?.host ?? "Repository")
                                Text(base).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                            .swipeActions { Button("Remove", role: .destructive) { store.removeRepository(base) } }
                    }
                    TextField("https://example.github.io/extensions/0.9/stable", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("Add repository", systemImage: "plus") {
                        do { try store.addRepository(address); address = ""; message = "Repository added or already present." }
                        catch { message = error.localizedDescription }
                    }.disabled(address.isEmpty)
                }
            }
            if let message { Section { Text(message).font(.footnote) } }
        }
        .searchable(text: $search, prompt: "Search installed extensions")
        .confirmationDialog("Remove extension?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            Button("Remove extension", role: .destructive) { if let info = pendingRemoval { store.remove(info) }; pendingRemoval = nil }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Library entries and downloads remain, but this source will be unavailable until the extension is reinstalled.")
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
