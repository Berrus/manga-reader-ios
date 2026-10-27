import SwiftUI

struct ServersView: View {
    private var store: ServerStore { .shared }
    @State private var addKind: ServerConfig.Kind?

    var body: some View {
        List {
            Section {
                ForEach(store.servers) { server in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                        Text("\(server.kind.label) · \(server.url)" + (server.username.isEmpty ? "" : " · \(server.username)"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .swipeActions {
                        Button("Remove", systemImage: "trash", role: .destructive) { store.remove(server) }
                    }
                }
                Button("Add Komga server…", systemImage: "plus") { addKind = .komga }
                if DistributionPolicy.allowsSuwayomi {
                    Button("Add Suwayomi server…", systemImage: "plus") { addKind = .suwayomi }
                }
            } footer: {
                Text("Connect to a media server you run yourself. Passwords are stored in the Keychain. Plain http:// is only allowed for servers on your local network. Suwayomi servers host extensions from third parties; what appears depends on your server.")
            }
        }
        .navigationTitle("Servers")
        .sheet(item: $addKind) { AddServerView(kind: $0) }
    }
}

struct AddServerView: View {
    let kind: ServerConfig.Kind
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var status: String?
    @State private var isTesting = false

    private var config: ServerConfig {
        ServerConfig(kind: kind, name: name.isEmpty ? url : name, url: url, username: username)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField(kind == .komga ? "http://192.168.1.10:25600" : "http://192.168.1.10:4567", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField(kind == .komga ? "Username" : "Username (optional)", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(kind == .komga ? "Password" : "Password (optional)", text: $password)
                }
                Section {
                    Button("Test connection") { test() }.disabled(isTesting || url.isEmpty)
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Add \(kind.label) server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ServerStore.shared.add(config, password: password)
                        dismiss()
                    }
                    .disabled(url.isEmpty || (kind == .komga && username.isEmpty))
                }
            }
        }
    }

    private func test() {
        isTesting = true
        status = nil
        let invalid = "That address isn't valid. Include http:// or https://."
        switch kind {
        case .komga:
            guard let source = KomgaSource(config: config, password: password) else { status = invalid; isTesting = false; return }
            Task {
                defer { isTesting = false }
                do { try await source.testConnection(); status = "Connected." }
                catch { status = error.localizedDescription }
            }
        case .suwayomi:
            guard let client = SuwayomiClient(config: config, password: password) else { status = invalid; isTesting = false; return }
            Task {
                defer { isTesting = false }
                do { status = "Connected to \(try await client.testConnection())." }
                catch { status = error.localizedDescription }
            }
        }
    }
}
