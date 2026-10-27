import SwiftUI

struct ServersView: View {
    private var store: ServerStore { .shared }
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                ForEach(store.servers) { server in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                        Text("\(server.url) · \(server.username)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .swipeActions {
                        Button("Remove", systemImage: "trash", role: .destructive) { store.remove(server) }
                    }
                }
                Button("Add Komga server…", systemImage: "plus") { showAdd = true }
                NavigationLink("Test Suwayomi connection") { SuwayomiConnectionView() }
            } footer: {
                Text("Connect to a media server you run yourself. Passwords are stored in the Keychain. Plain http:// is only allowed for servers on your local network.")
            }
        }
        .navigationTitle("Servers")
        .sheet(isPresented: $showAdd) { AddServerView() }
    }
}

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var status: String?
    @State private var isTesting = false

    private var config: ServerConfig {
        ServerConfig(name: name.isEmpty ? url : name, url: url, username: username)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("http://192.168.1.10:25600", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }
                Section {
                    Button("Test connection") { test() }.disabled(isTesting || url.isEmpty)
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Add server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ServerStore.shared.add(config, password: password)
                        dismiss()
                    }
                    .disabled(url.isEmpty || username.isEmpty)
                }
            }
        }
    }

    private func test() {
        guard let source = KomgaSource(config: config, password: password) else {
            status = "That address isn't valid. Include http:// or https://."
            return
        }
        isTesting = true
        status = nil
        Task {
            defer { isTesting = false }
            do { try await source.testConnection(); status = "Connected." }
            catch { status = error.localizedDescription }
        }
    }
}
