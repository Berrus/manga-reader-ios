#if !APP_STORE
import Foundation
import Observation

/// Installed JavaScript sources: a manifest (`<id>.json`) plus the verified script (`<id>.js`).
/// Off by default; nothing is bundled and no catalog is pre-filled.
@MainActor @Observable
final class ScriptedSourceStore {
    static let shared = ScriptedSourceStore()
    private static let enabledKey = "scriptedSourcesEnabled"
    var enabled = false
    private(set) var manifests: [ScriptedSourceManifest] = []
    @ObservationIgnored private var cache: [String: ScriptedSource] = [:]

    init() {
        enabled = DistributionPolicy.allowsScriptedSources && UserDefaults.standard.bool(forKey: Self.enabledKey)
        load()
    }
    func persistEnabled() {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if !enabled { cache.removeAll() }
    }

    private var directory: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("ScriptedSources", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        manifests = files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? JSONDecoder().decode(ScriptedSourceManifest.self, from: data),
                  (try? ScriptedSource.validate(manifest)) != nil else { return nil }
            return manifest
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Reads a manifest from an HTTPS address. Data only; nothing is run.
    func fetchManifest(from url: URL) async throws -> ScriptedSourceManifest {
        guard let host = url.host, url.scheme == "https" else { throw ScriptedSourceError.invalid("Use an HTTPS address.") }
        let (data, _) = try await SourceTransport.load(URLRequest(url: url),
                                                       policy: SourceAccessPolicy(hosts: [host]), maxBytes: 64_000)
        let manifest = try JSONDecoder().decode(ScriptedSourceManifest.self, from: data)
        try ScriptedSource.validate(manifest)
        return manifest
    }

    /// Shown before installing when the id exists with other domains or a different script.
    func replacementWarning(for new: ScriptedSourceManifest) -> String? {
        guard let old = manifests.first(where: { $0.id == new.id }) else { return nil }
        let oldHosts = Set(old.hosts.map { $0.lowercased() }), newHosts = Set(new.hosts.map { $0.lowercased() })
        guard oldHosts != newHosts || old.sha256.lowercased() != new.sha256.lowercased() else { return nil }
        var text = "This replaces the installed script source \(old.name) (version \(old.version))."
        if oldHosts != newHosts {
            text += " It will contact \(newHosts.sorted().joined(separator: ", ")) instead of \(oldHosts.sorted().joined(separator: ", "))."
        }
        return text + " Only continue if you trust it."
    }

    /// Downloads the script, checks its SHA-256 against the manifest, then saves both.
    func install(_ manifest: ScriptedSourceManifest) async throws {
        guard DistributionPolicy.allowsScriptedSources else { throw ScriptedSourceError.invalid("Not available in this build.") }
        try ScriptedSource.validate(manifest)
        guard let url = URL(string: manifest.entry), let host = url.host else { throw ScriptedSourceError.invalid("Bad script address.") }
        let (data, _) = try await SourceTransport.load(URLRequest(url: url),
            policy: SourceAccessPolicy(hosts: [host]), maxBytes: ScriptedSource.maxScriptBytes)
        guard let script = String(data: data, encoding: .utf8) else { throw ScriptedSourceError.invalid("Script is not text.") }
        _ = try ScriptedSource(manifest: manifest, script: script) // verifies size and checksum
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("\(manifest.id).json"), options: .atomic)
        try data.write(to: directory.appendingPathComponent("\(manifest.id).js"), options: .atomic)
        cache[manifest.id] = nil
        manifests.removeAll { $0.id == manifest.id }
        manifests.append(manifest)
        manifests.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func remove(_ manifest: ScriptedSourceManifest) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(manifest.id).json"))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(manifest.id).js"))
        cache[manifest.id] = nil
        manifests.removeAll { $0.id == manifest.id }
    }

    /// The script is re-hashed on every load, so a file changed on disk is refused.
    func source(for manifest: ScriptedSourceManifest) -> ScriptedSource? {
        guard enabled, DistributionPolicy.allowsScriptedSources else { return nil }
        if let cached = cache[manifest.id] { return cached }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("\(manifest.id).js")),
              data.count <= ScriptedSource.maxScriptBytes, let script = String(data: data, encoding: .utf8),
              let source = try? ScriptedSource(manifest: manifest, script: script) else { return nil }
        cache[manifest.id] = source
        return source
    }
    func source(id: String) -> ScriptedSource? {
        guard id.hasPrefix("js."), let manifest = manifests.first(where: { "js." + $0.id == id }) else { return nil }
        return source(for: manifest)
    }
}
#endif
