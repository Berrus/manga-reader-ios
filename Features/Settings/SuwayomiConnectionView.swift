import SwiftUI

/// Tests a user-provided Suwayomi endpoint without persisting credentials.
struct SuwayomiConnectionView: View {
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var sources: [SuwayomiResponse.Source] = []

    var body: some View {
        Form {
            Section {
                TextField("https://server.example.com", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Username (optional)", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password (optional)", text: $password)
                Button(busy ? "Testing…" : "Test connection", action: test).disabled(busy)
            } header: {
                Text("Server")
            } footer: {
                Text("This connection test supports HTTPS and optional HTTP Basic authentication. It lists up to 200 installed sources. It does not save the server, install sources, or read manga.")
            }
            if let message { Section { Text(message) } }
            if !sources.isEmpty {
                Section("Installed sources (first 200)") {
                    ForEach(sources, id: \.id) { source in
                        VStack(alignment: .leading) {
                            Text(source.displayName)
                            Text(source.lang).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Suwayomi")
    }

    private func test() {
        guard let base = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              base.scheme == "https", let host = base.host, base.user == nil, base.password == nil else {
            message = "Enter an HTTPS server address without credentials."; return
        }
        let endpoint = base.appendingPathComponent("api/graphql")
        let policy = SourceAccessPolicy(hosts: [host], port: base.port ?? 443)
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !username.isEmpty || !password.isEmpty {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": "{ aboutServer { name version } sources(first: 200) { nodes { id displayName lang } } }"])
        busy = true; message = nil; sources = []
        Task {
            defer { busy = false }
            do {
                let (data, _) = try await SourceTransport.load(request, policy: policy, maxBytes: 100_000)
                let result = try JSONDecoder().decode(SuwayomiResponse.self, from: data)
                guard result.errors?.isEmpty != false, let server = result.data?.aboutServer,
                      let installed = result.data?.sources?.nodes else {
                    throw JSSourceError.invalidManifest("Server did not return Suwayomi information.")
                }
                sources = installed
                message = "Connected to \(server.name), version \(server.version). Found \(installed.count) installed sources (up to 200)."
            } catch { message = "Connection failed: \(error.localizedDescription)" }
        }
    }

}

struct SuwayomiResponse: Decodable {
    struct Source: Decodable { let id: String; let displayName: String; let lang: String }
    struct Server: Decodable { let name: String; let version: String }
    struct SourceList: Decodable { let nodes: [Source] }
    struct ResponseData: Decodable { let aboutServer: Server?; let sources: SourceList? }
    struct GraphQLError: Decodable { let message: String }
    let data: ResponseData?
    let errors: [GraphQLError]?
}
