import SwiftUI

/// Tests a user-provided Suwayomi endpoint without persisting credentials.
struct SuwayomiConnectionView: View {
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Server") {
                TextField("https://server.example.com", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Username (optional)", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password (optional)", text: $password)
                Button(busy ? "Testing…" : "Test connection", action: test).disabled(busy)
            } footer: {
                Text("This connection test supports HTTPS and optional HTTP Basic authentication. It does not save the server or install sources.")
            }
            if let message { Section { Text(message) } }
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
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": "{ aboutServer { name version } }"])
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let (data, _) = try await SourceTransport.load(request, policy: policy, maxBytes: 100_000)
                let result = try JSONDecoder().decode(ServerResponse.self, from: data)
                guard let server = result.data?.aboutServer else {
                    throw JSSourceError.invalidManifest("Server did not return Suwayomi information.")
                }
                message = "Connected to \(server.name), version \(server.version)."
            } catch { message = "Connection failed: \(error.localizedDescription)" }
        }
    }

    private struct ServerResponse: Decodable {
        struct ResponseData: Decodable {
            struct Server: Decodable { let name: String; let version: String }
            let aboutServer: Server?
        }
        let data: ResponseData?
    }
}
