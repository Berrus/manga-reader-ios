import Foundation

struct SourceEndpoint: Codable, Hashable {
    var url: String
    var itemsPath: String? = nil
    var fields: [String: String]
}

/// Name retained for decoding older installations; scripts are never evaluated.
struct JSSourceManifest: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var version: String
    var hosts: [String]
    var script: String = ""
    var endpoints: [String: SourceEndpoint] = [:]

    enum CodingKeys: String, CodingKey { case id, name, version, hosts, script, endpoints }
    init(id: String, name: String, version: String, hosts: [String], script: String = "",
         endpoints: [String: SourceEndpoint] = [:]) {
        self.id = id; self.name = name; self.version = version; self.hosts = hosts
        self.script = script; self.endpoints = endpoints
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        hosts = try c.decode([String].self, forKey: .hosts)
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        endpoints = try c.decodeIfPresent([String: SourceEndpoint].self, forKey: .endpoints) ?? [:]
    }
}

enum JSSourceError: LocalizedError {
    case invalidManifest(String), scriptFailed(String)
    var errorDescription: String? {
        switch self {
        case .invalidManifest(let message): return "Invalid source: \(message)"
        case .scriptFailed(let message): return "Source error: \(message)"
        }
    }
}

/// A bounded declarative JSON endpoint adapter. No JavaScript or downloaded programs.
final class JSSource: Source, @unchecked Sendable {
    let manifest: JSSourceManifest
    var id: String { manifest.id }
    var name: String { manifest.name }
    var accessPolicy: SourceAccessPolicy { SourceAccessPolicy(hosts: manifest.hosts) }
    init(manifest: JSSourceManifest) throws {
        try SourceStore.validate(manifest)
        self.manifest = manifest
    }

    func search(query: String, page: Int) async throws -> [MangaSummary] {
        let rows = try await records("search", ["query": query, "page": String(page)])
        return try rows.map {
            MangaSummary(id: try required("id", in: $0), title: try required("title", in: $0),
                         coverURL: try imageURL($0["coverURL"]))
        }
    }
    func details(for manga: MangaSummary) async throws -> MangaDetails {
        guard let row = try await records("details", ["id": manga.id]).first else {
            throw JSSourceError.scriptFailed("No details returned.")
        }
        return MangaDetails(title: row["title"], coverURL: try imageURL(row["coverURL"]),
                            author: row["author"], summary: row["summary"])
    }
    func chapters(for manga: MangaSummary) async throws -> [ChapterSummary] {
        try await records("chapters", ["id": manga.id]).map {
            ChapterSummary(id: try required("id", in: $0), name: try required("name", in: $0),
                           number: $0["number"].flatMap(Double.init))
        }
    }
    func pages(for chapter: ChapterSummary) async throws -> [PageSource] {
        try await records("pages", ["id": chapter.id]).map {
            PageSource(url: try requiredImageURL(try required("url", in: $0)), headers: nil)
        }
    }

    private func required(_ key: String, in row: [String: String]) throws -> String {
        guard let value = row[key], !value.isEmpty else { throw JSSourceError.scriptFailed("Missing \(key).") }
        return value
    }
    private func imageURL(_ value: String?) throws -> String? {
        try value.map { try requiredImageURL($0) }
    }
    private func requiredImageURL(_ value: String) throws -> String {
        guard let url = URL(string: value), accessPolicy.allows(url) else { throw TransportError.blocked }
        return value
    }

    private func records(_ operation: String, _ values: [String: String]) async throws -> [[String: String]] {
        guard let endpoint = manifest.endpoints[operation] else { throw JSSourceError.scriptFailed("Missing \(operation) endpoint.") }
        var address = endpoint.url
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        for (key, value) in values {
            address = address.replacingOccurrences(of: "{\(key)}", with: value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }
        guard let url = URL(string: address), accessPolicy.allows(url) else { throw TransportError.blocked }
        let (data, _) = try await SourceTransport.load(URLRequest(url: url), policy: accessPolicy, maxBytes: 10_000_000)
        let object = try JSONSerialization.jsonObject(with: data)
        let selected = Self.value(at: endpoint.itemsPath ?? "", in: object)
        let rows = (selected as? [Any]) ?? selected.map { [$0] } ?? []
        guard rows.count <= 10_000 else { throw TransportError.tooLarge }
        return rows.map { object in
            var mapped: [String: String] = [:]
            for (field, path) in endpoint.fields {
                let value = Self.value(at: path, in: object)
                if let text = value as? String { mapped[field] = text }
                else if let number = value as? NSNumber { mapped[field] = number.stringValue }
            }
            return mapped
        }
    }

    static func value(at path: String, in object: Any) -> Any? {
        if path.isEmpty { return object }
        return path.split(separator: ".").reduce(Optional(object)) { current, key in
            if let dictionary = current as? [String: Any] { return dictionary[String(key)] }
            if let array = current as? [Any], let index = Int(key), array.indices.contains(index) { return array[index] }
            return nil
        }
    }
}
