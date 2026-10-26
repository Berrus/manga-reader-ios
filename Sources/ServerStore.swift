import Foundation
import Observation

struct ServerConfig: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case komga }

    var id = UUID()
    var kind: Kind = .komga
    var name: String
    var url: String
    var username: String
}

/// User-owned servers. Passwords are kept in the Keychain, never in the saved list.
@MainActor @Observable
final class ServerStore {
    static let shared = ServerStore()

    private(set) var servers: [ServerConfig] = []

    init() { load() }

    private var fileURL: URL {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("servers.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([ServerConfig].self, from: data) else { return }
        servers = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(servers) { try? data.write(to: fileURL, options: .atomic) }
    }

    static func account(for id: UUID) -> String { "server.\(id.uuidString)" }

    func password(for server: ServerConfig) -> String {
        Keychain.get(Self.account(for: server.id)) ?? ""
    }

    func add(_ server: ServerConfig, password: String) {
        Keychain.set(password, for: Self.account(for: server.id))
        servers.append(server)
        save()
    }

    func remove(_ server: ServerConfig) {
        Keychain.remove(Self.account(for: server.id))
        servers.removeAll { $0.id == server.id }
        save()
    }

    func source(for server: ServerConfig) -> (any Source)? {
        guard let source = KomgaSource(config: server, password: password(for: server)) else { return nil }
        return source
    }
}
