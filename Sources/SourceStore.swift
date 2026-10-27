import Foundation
import Observation

@MainActor @Observable
final class SourceStore {
    static let shared = SourceStore()
    private static let enabledKey = "customSourcesEnabled"
    nonisolated static let maxScriptBytes = 512_000
    var enabled = false
    private(set) var manifests: [JSSourceManifest] = []
    private(set) var migrationMessage: String?
    @ObservationIgnored private var cache: [String: JSSource] = [:]

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        load()
    }
    func persistEnabled() {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if !enabled { cache.removeAll() }
    }
    private var directory: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var rejected = 0
        manifests = files.filter { $0.pathExtension == "json" }.compactMap { url in
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: Self.maxScriptBytes + 4097) ?? Data()
                guard data.count <= Self.maxScriptBytes + 4096 else { throw TransportError.tooLarge }
                let manifest = try JSONDecoder().decode(JSSourceManifest.self, from: data)
                try Self.validate(manifest)
                return manifest
            } catch { rejected += 1; return nil }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if rejected > 0 { migrationMessage = "\(rejected) older or invalid source definitions were disabled. Replace script definitions with declarative JSON; original files were retained." }
    }
    func fetchManifest(from url: URL) async throws -> JSSourceManifest {
        guard let host = url.host, url.scheme == "https" else {
            throw JSSourceError.invalidManifest("Use an HTTPS address.")
        }
        let (data, _) = try await SourceTransport.load(URLRequest(url: url),
            policy: SourceAccessPolicy(hosts: [host]), maxBytes: Self.maxScriptBytes + 4096)
        let manifest = try JSONDecoder().decode(JSSourceManifest.self, from: data)
        try Self.validate(manifest) // Data validation only; never runs code or requests endpoints.
        return manifest
    }
    func add(_ manifest: JSSourceManifest, origin: String? = nil) throws {
        try Self.validate(manifest)
        let data = try JSONEncoder().encode(manifest)
        guard data.count <= Self.maxScriptBytes + 4096 else { throw TransportError.tooLarge }
        try data.write(to: directory.appendingPathComponent("\(manifest.id).json"), options: .atomic)
        if let origin { setOrigin(origin, for: manifest.id) }
        cache[manifest.id] = nil
        manifests.removeAll { $0.id == manifest.id }
        manifests.append(manifest)
        manifests.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    // MARK: Provenance

    private static let originsKey = "sourceOrigins"

    /// Repository address a source was installed from, if it came from one.
    func origin(of id: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: Self.originsKey) as? [String: String])?[id]
    }

    private func setOrigin(_ origin: String?, for id: String) {
        var all = (UserDefaults.standard.dictionary(forKey: Self.originsKey) as? [String: String]) ?? [:]
        all[id] = origin
        UserDefaults.standard.set(all, forKey: Self.originsKey)
    }

    /// A warning to show before installing `new` when it would replace an installed source with
    /// different domains or from a different repository. Nil means nothing unusual.
    func replacementWarning(for new: JSSourceManifest, origin: String?) -> String? {
        guard let existing = manifests.first(where: { $0.id == new.id }) else { return nil }
        return Self.replacementWarning(existing: existing, existingOrigin: self.origin(of: new.id),
                                       new: new, newOrigin: origin)
    }

    nonisolated static func replacementWarning(existing: JSSourceManifest, existingOrigin: String?,
                                               new: JSSourceManifest, newOrigin: String?) -> String? {
        let oldHosts = Set(existing.hosts.map { $0.lowercased() })
        let newHosts = Set(new.hosts.map { $0.lowercased() })
        let hostsChanged = oldHosts != newHosts
        // Sources installed before origins were recorded have none, so only a known mismatch counts.
        let originChanged = existingOrigin != nil && existingOrigin != newOrigin
        guard hostsChanged || originChanged else { return nil }
        var text = "This replaces the installed source \(existing.name) (version \(existing.version))."
        if hostsChanged {
            text += " It will contact \(newHosts.sorted().joined(separator: ", ")) instead of \(oldHosts.sorted().joined(separator: ", "))."
        }
        if originChanged { text += " It comes from a different repository than the one you installed it from." }
        return text + " Only continue if you trust it."
    }

    func remove(_ manifest: JSSourceManifest) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(manifest.id).json"))
        cache[manifest.id] = nil
        setOrigin(nil, for: manifest.id)
        manifests.removeAll { $0.id == manifest.id }
    }
    func source(for manifest: JSSourceManifest) -> JSSource? {
        guard enabled else { return nil }
        if let source = cache[manifest.id] { return source }
        guard let source = try? JSSource(manifest: manifest) else { return nil }
        cache[manifest.id] = source
        return source
    }

    nonisolated static func validate(_ manifest: JSSourceManifest) throws {
        func matches(_ value: String, _ pattern: String) -> Bool {
            value.range(of: pattern, options: .regularExpression) != nil
        }
        guard manifest.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JSSourceError.invalidManifest("Executable scripts are not supported. Use declarative JSON endpoints.")
        }
        guard matches(manifest.id, #"^[a-z0-9][a-z0-9._-]{0,63}$"#),
              !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 200 else { throw JSSourceError.invalidManifest("Invalid id or name.") }
        guard !manifest.hosts.isEmpty, manifest.hosts.count <= 20,
              manifest.hosts.allSatisfy({ matches($0.lowercased(), #"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$"#) })
        else { throw JSSourceError.invalidManifest("Declare the domains this source uses.") }
        let policy = SourceAccessPolicy(hosts: manifest.hosts)
        for name in ["search", "details", "chapters", "pages"] {
            guard let endpoint = manifest.endpoints[name], endpoint.url.count <= 2048,
                  endpoint.fields.count <= 20 else { throw JSSourceError.invalidManifest("Missing or invalid \(name) endpoint.") }
            var sample = endpoint.url
            for token in ["{query}", "{page}", "{id}"] { sample = sample.replacingOccurrences(of: token, with: "sample") }
            guard !sample.contains("{"), !sample.contains("}"), let url = URL(string: sample), policy.allows(url),
                  (endpoint.itemsPath?.count ?? 0) <= 128,
                  endpoint.fields.values.allSatisfy({ $0.count <= 128 }) else {
                throw JSSourceError.invalidManifest("Endpoints must use HTTPS and declared hosts.")
            }
            let required = name == "search" ? ["id", "title"] : name == "chapters" ? ["id", "name"] : name == "pages" ? ["url"] : []
            guard required.allSatisfy({ endpoint.fields[$0] != nil }) else {
                throw JSSourceError.invalidManifest("Missing required \(name) fields.")
            }
        }
    }
}
