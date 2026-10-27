import Foundation
import Observation

struct ServerConfig: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, Identifiable {
        case komga, suwayomi, opds
        var id: String { rawValue }
        var label: String {
            switch self {
            case .komga: return "Komga"
            case .suwayomi: return "Suwayomi"
            case .opds: return "OPDS"
            }
        }
    }

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

    /// A single source for the server. Suwayomi servers host many sources, so they have none here;
    /// use `suwayomiClient(for:)` and `suwayomiSource(...)` instead.
    func source(for server: ServerConfig) -> (any Source)? {
        switch server.kind {
        case .komga: return KomgaSource(config: server, password: password(for: server))
        case .opds: return OPDSSource(config: server, password: password(for: server))
        case .suwayomi: return nil
        }
    }

    func suwayomiClient(for server: ServerConfig) -> SuwayomiClient? {
        guard server.kind == .suwayomi, DistributionPolicy.allowsSuwayomi else { return nil }
        return SuwayomiClient(config: server, password: password(for: server))
    }

    func suwayomiSource(serverID: UUID, sourceID: String, name: String = "Suwayomi") -> SuwayomiSource? {
        guard DistributionPolicy.allowsSuwayomi,
              let server = servers.first(where: { $0.id == serverID && $0.kind == .suwayomi }) else { return nil }
        return SuwayomiSource(config: server, password: password(for: server), sourceID: sourceID, name: name)
    }
}
