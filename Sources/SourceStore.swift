import Foundation
import Observation

/// Installed custom sources. The whole feature is off until the user turns it on, and the app
/// ships with no sources and no repository addresses.
@MainActor @Observable
final class SourceStore {
    static let shared = SourceStore()

    private static let enabledKey = "customSourcesEnabled"
    static let maxScriptBytes = 512_000

    var enabled: Bool = UserDefaults.standard.bool(forKey: SourceStore.enabledKey) {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }

    private(set) var manifests: [JSSourceManifest] = []
    @ObservationIgnored private var cache: [String: JSSource] = [:]

    init() { load() }

    private var directory: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        manifests = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(JSSourceManifest.self, from: data)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Downloads and validates a source definition without installing it.
    func fetchManifest(from url: URL) async throws -> JSSourceManifest {
        guard url.scheme == "https" else {
            throw JSSourceError.invalidManifest("The address must start with https://")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw JSSourceError.invalidManifest("The server didn't return the file.")
        }
        guard data.count <= Self.maxScriptBytes + 4_096 else {
            throw JSSourceError.invalidManifest("The file is too large.")
        }
        let manifest: JSSourceManifest
        do { manifest = try JSONDecoder().decode(JSSourceManifest.self, from: data) }
        catch { throw JSSourceError.invalidManifest("The file isn't a valid source definition.") }
        try Self.validate(manifest)
        return manifest
    }

    func add(_ manifest: JSSourceManifest) throws {
        try Self.validate(manifest)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent("\(manifest.id).json"), options: .atomic)
        cache[manifest.id] = nil
        manifests.removeAll { $0.id == manifest.id }
        manifests.append(manifest)
        manifests.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func remove(_ manifest: JSSourceManifest) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(manifest.id).json"))
        cache[manifest.id] = nil
        manifests.removeAll { $0.id == manifest.id }
    }

    func source(for manifest: JSSourceManifest) -> JSSource? {
        guard enabled else { return nil }
        if let cached = cache[manifest.id] { return cached }
        guard let source = try? JSSource(manifest: manifest) else { return nil }
        cache[manifest.id] = source
        return source
    }

    static func validate(_ manifest: JSSourceManifest) throws {
        func matches(_ s: String, _ pattern: String) -> Bool {
            s.range(of: pattern, options: .regularExpression) != nil
        }
        guard matches(manifest.id, #"^[a-z0-9][a-z0-9._-]{0,63}$"#) else {
            throw JSSourceError.invalidManifest("id must be lowercase letters, numbers, dots, dashes.")
        }
        guard !manifest.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw JSSourceError.invalidManifest("missing name.")
        }
        guard !manifest.hosts.isEmpty,
              manifest.hosts.allSatisfy({ matches($0.lowercased(), #"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$"#) }) else {
            throw JSSourceError.invalidManifest("hosts must be a list of domain names, e.g. example.com.")
        }
        guard manifest.script.utf8.count <= maxScriptBytes else {
            throw JSSourceError.invalidManifest("script is too large.")
        }
        _ = try JSSource(manifest: manifest)  // make sure the script loads
    }
}
