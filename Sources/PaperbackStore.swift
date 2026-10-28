#if !APP_STORE
import Foundation
import Observation

/// Paperback 0.9 extension repositories and the extensions installed from them.
/// Off by default; no repository address is built in.
@MainActor @Observable
final class PaperbackStore {
    static let shared = PaperbackStore()
    private static let enabledKey = "paperbackEnabled", repositoriesKey = "paperbackRepositories"
    var enabled = false
    private(set) var disabledIDs: Set<String> = []
    private(set) var repositories: [String] = []
    private(set) var installed: [PaperbackExtensionInfo] = []
    @ObservationIgnored private var cache: [String: PaperbackSource] = [:]

    init() {
        let defaults = UserDefaults.standard
        enabled = DistributionPolicy.allowsScriptedSources && defaults.bool(forKey: Self.enabledKey)
        repositories = defaults.stringArray(forKey: Self.repositoriesKey) ?? []
        disabledIDs = Set(defaults.stringArray(forKey: "paperbackDisabledIDs") ?? [])
        load()
    }
    func persistEnabled() {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if !enabled { cache.removeAll() }
    }

    func isEnabled(_ info: PaperbackExtensionInfo) -> Bool { !disabledIDs.contains(info.id) }
    func setEnabled(_ value: Bool, for info: PaperbackExtensionInfo) {
        if value { disabledIDs.remove(info.id) } else { disabledIDs.insert(info.id) }
        UserDefaults.standard.set(Array(disabledIDs), forKey: "paperbackDisabledIDs")
        cache["pb." + info.id] = nil
    }

    private var directory: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("PaperbackSources", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func load() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        installed = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("info.json")),
                  let info = try? JSONDecoder().decode(PaperbackExtensionInfo.self, from: data),
                  PaperbackExtensionInfo.isValidID(info.id), info.isAllowed else { return nil }
            return info
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Repositories

    /// Accepts the base address a user pastes, with or without a trailing slash or `/versioning.json`.
    nonisolated static func normalizedBase(_ text: String) -> String? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/versioning.json") { trimmed = String(trimmed.dropLast("/versioning.json".count)) }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard trimmed.count <= 2048, let url = URL(string: trimmed), url.scheme == "https", let host = url.host,
              !SourceAccessPolicy.isLocal(host), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return trimmed
    }

    func addRepository(_ text: String) throws {
        guard let base = Self.normalizedBase(text) else { throw PaperbackError.invalid("Use an HTTPS repository address.") }
        guard repositories.count < 20 else { throw PaperbackError.invalid("At most 20 repositories.") }
        guard !repositories.contains(where: { $0.caseInsensitiveCompare(base) == .orderedSame }) else { return }
        repositories.append(base)
        UserDefaults.standard.set(repositories, forKey: Self.repositoriesKey)
    }
    func removeRepository(_ base: String) {
        repositories.removeAll { $0 == base }
        UserDefaults.standard.set(repositories, forKey: Self.repositoriesKey)
    }

    private func policy(for base: String) throws -> SourceAccessPolicy {
        guard let host = URL(string: base)?.host else { throw PaperbackError.invalid("Bad repository address.") }
        return SourceAccessPolicy(hosts: [host])
    }

    /// Lists what a repository offers. Entries with a bad id or an ADULT rating are dropped.
    func index(of base: String) async throws -> [PaperbackExtensionInfo] {
        guard let url = URL(string: base + "/versioning.json") else { throw PaperbackError.invalid("Bad repository address.") }
        let (data, _) = try await SourceTransport.load(URLRequest(url: url), policy: try policy(for: base), maxBytes: 2_000_000)
        return Self.parseIndex(data, base: base)
    }
    nonisolated static func parseIndex(_ data: Data, base: String) -> [PaperbackExtensionInfo] {
        struct Lossy: Decodable {
            let value: PaperbackExtensionInfo?
            init(from decoder: Decoder) throws { value = try? PaperbackExtensionInfo(from: decoder) }
        }
        struct Index: Decodable { var sources: [Lossy] }
        let rows = (try? JSONDecoder().decode(Index.self, from: data))?.sources ?? []
        return rows.prefix(500).compactMap(\.value).filter { PaperbackExtensionInfo.isValidID($0.id) && $0.isAllowed }.map {
            var info = $0; info.repository = base; return info
        }
    }

    // MARK: Extensions

    func install(_ info: PaperbackExtensionInfo, from base: String) async throws {
        guard DistributionPolicy.allowsScriptedSources else { throw PaperbackError.invalid("Not available in this build.") }
        guard PaperbackExtensionInfo.isValidID(info.id), info.isAllowed,
              let url = URL(string: base + "/" + info.id + "/index.js") else { throw PaperbackError.invalid("Extension not allowed.") }
        let (data, _) = try await SourceTransport.load(URLRequest(url: url), policy: try policy(for: base),
                                                       maxBytes: PaperbackSource.maxScriptBytes)
        guard let script = String(data: data, encoding: .utf8) else { throw PaperbackError.invalid("The extension is not text.") }
        var stored = info
        stored.repository = base
        _ = try PaperbackSource(info: stored, script: script)
        let folder = directory.appendingPathComponent(info.id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent("index.js"), options: .atomic)
        try JSONEncoder().encode(stored).write(to: folder.appendingPathComponent("info.json"), options: .atomic)
        cache["pb." + info.id] = nil
        installed.removeAll { $0.id == info.id }
        installed.append(stored)
        installed.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func remove(_ info: PaperbackExtensionInfo) {
        guard PaperbackExtensionInfo.isValidID(info.id) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(info.id, isDirectory: true))
        cache["pb." + info.id] = nil
        installed.removeAll { $0.id == info.id }
    }

    func source(for info: PaperbackExtensionInfo) -> PaperbackSource? {
        guard enabled, DistributionPolicy.allowsScriptedSources, isEnabled(info) else { return nil }
        if let cached = cache["pb." + info.id] { return cached }
        let file = directory.appendingPathComponent(info.id, isDirectory: true).appendingPathComponent("index.js")
        guard let data = try? Data(contentsOf: file), let script = String(data: data, encoding: .utf8),
              let source = try? PaperbackSource(info: info, script: script) else { return nil }
        cache["pb." + info.id] = source
        return source
    }
    func source(id: String) -> PaperbackSource? {
        installed.first(where: { "pb." + $0.id == id }).flatMap { source(for: $0) }
    }
}
#endif
