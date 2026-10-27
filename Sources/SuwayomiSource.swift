import Foundation

enum SuwayomiError: LocalizedError {
    case server(String)
    case unauthorized
    case notSuwayomi
    case badIdentifier

    var errorDescription: String? {
        switch self {
        case .server(let message): return "Suwayomi error: \(message)"
        case .unauthorized:
            return "The server refused the sign-in. Check the username and password. Only servers with no login or HTTP Basic authentication are supported."
        case .notSuwayomi: return "That address doesn't look like a Suwayomi server. Check the address and port."
        case .badIdentifier: return "The server returned an unexpected identifier."
        }
    }
}

/// A source (extension) installed on a Suwayomi server.
struct SuwayomiSourceInfo: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let lang: String
    let displayName: String
    let isNsfw: Bool

    private enum CodingKeys: String, CodingKey { case id, name, lang, displayName, isNsfw }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Source ids are 64-bit numbers; servers send them as strings, but accept numbers too.
        if let text = try? c.decode(String.self, forKey: .id) { id = text }
        else { id = String(try c.decode(Int64.self, forKey: .id)) }
        name = try c.decode(String.self, forKey: .name)
        lang = (try? c.decode(String.self, forKey: .lang)) ?? ""
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? name
        isNsfw = (try? c.decode(Bool.self, forKey: .isNsfw)) ?? false
    }

    init(id: String, name: String, lang: String, displayName: String? = nil, isNsfw: Bool = false) {
        self.id = id; self.name = name; self.lang = lang
        self.displayName = displayName ?? name; self.isNsfw = isNsfw
    }
}

/// Client for a user-owned Suwayomi server: GraphQL at `/api/graphql`, no login or HTTP Basic auth.
/// Suwayomi hosts third-party extensions, so what it serves depends entirely on the user's server.
struct SuwayomiClient: Sendable {
    let base: URL
    let authorization: String?

    init?(config: ServerConfig, password: String) {
        var text = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        base = url
        if config.username.isEmpty && password.isEmpty { authorization = nil }
        else {
            authorization = "Basic " + Data("\(config.username):\(password)".utf8).base64EncodedString()
        }
        guard accessPolicy.allows(base) else { return nil }
    }

    var accessPolicy: SourceAccessPolicy {
        SourceAccessPolicy(hosts: [base.host ?? ""], allowsLocalHTTP: true,
                           port: base.port ?? (base.scheme == "https" ? 443 : 80))
    }

    var imageHeaders: [String: String] { authorization.map { ["Authorization": $0] } ?? [:] }

    // MARK: Server-level calls

    /// Returns the server name and version, e.g. "Suwayomi 1.1.0".
    func testConnection() async throws -> String {
        let data: AboutData = try await run("{ aboutServer { name version } }")
        guard let about = data.aboutServer else { throw SuwayomiError.notSuwayomi }
        return "\(about.name) \(about.version)"
    }

    func sources() async throws -> [SuwayomiSourceInfo] {
        let data: SourcesData = try await run("{ sources { nodes { id name lang displayName isNsfw } } }")
        return Self.visibleSources(data.sources.nodes)
    }

    /// Adult-only sources are left out, matching the rest of the app.
    static func visibleSources(_ all: [SuwayomiSourceInfo]) -> [SuwayomiSourceInfo] {
        all.filter { !$0.isNsfw }.sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame ? $0.lang < $1.lang : order == .orderedAscending
        }
    }

    // MARK: Transport

    static func body(query: String, variables: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
    }

    func run<T: Decodable>(_ query: String, _ variables: [String: Any] = [:]) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent("api/graphql"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        request.httpBody = try Self.body(query: query, variables: variables)

        let data: Data
        do { (data, _) = try await SourceTransport.load(request, policy: accessPolicy, maxBytes: 10_000_000) }
        catch let TransportError.http(code) where code == 401 || code == 403 { throw SuwayomiError.unauthorized }
        catch let TransportError.http(code) where code == 404 { throw SuwayomiError.notSuwayomi }
        return try Self.decode(data)
    }

    static func decode<T: Decodable>(_ data: Data) throws -> T {
        let envelope: Envelope<T>
        do { envelope = try JSONDecoder().decode(Envelope<T>.self, from: data) }
        catch { throw SuwayomiError.notSuwayomi }
        if let message = envelope.errors?.first?.message { throw SuwayomiError.server(message) }
        guard let payload = envelope.data else { throw SuwayomiError.notSuwayomi }
        return payload
    }

    /// Page and thumbnail paths come back relative to the server (e.g. `/api/v1/manga/3/thumbnail`).
    /// A server mounted under a sub-path keeps that prefix.
    static func absoluteURL(_ path: String, base: URL) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        let separator = path.hasPrefix("/") ? "" : "/"
        return URL(string: base.absoluteString + separator + path)
    }

    // MARK: Response models

    struct Envelope<T: Decodable>: Decodable {
        struct GraphQLError: Decodable { let message: String }
        let data: T?
        let errors: [GraphQLError]?
    }

    struct AboutData: Decodable {
        struct About: Decodable { let name: String; let version: String }
        let aboutServer: About?
    }

    struct SourcesData: Decodable {
        struct Nodes: Decodable { let nodes: [SuwayomiSourceInfo] }
        let sources: Nodes
    }

    struct MangaNode: Decodable {
        let id: Int
        let title: String
        let thumbnailUrl: String?
        let author: String?
        let artist: String?
        let description: String?
    }

    struct ChapterNode: Decodable {
        let id: Int
        let name: String
        let chapterNumber: Double?
        let sourceOrder: Int?
    }

    struct SourceMangaData: Decodable {
        struct Payload: Decodable { let mangas: [MangaNode]; let hasNextPage: Bool? }
        let fetchSourceManga: Payload
    }

    struct MangaDetailData: Decodable {
        struct Payload: Decodable { let manga: MangaNode }
        let fetchManga: Payload
    }

    struct ChaptersData: Decodable {
        struct Payload: Decodable { let chapters: [ChapterNode] }
        let fetchChapters: Payload
    }

    struct PagesData: Decodable {
        struct Payload: Decodable { let pages: [String] }
        let fetchChapterPages: Payload
    }
}

/// One extension source on a Suwayomi server, exposed through the app's common `Source` protocol.
struct SuwayomiSource: Source {
    let id: String
    let name: String
    private let client: SuwayomiClient
    private let sourceID: String

    var imageHeaders: [String: String] { client.imageHeaders }
    var accessPolicy: SourceAccessPolicy { client.accessPolicy }

    init?(config: ServerConfig, password: String, sourceID: String, name: String) {
        guard let client = SuwayomiClient(config: config, password: password) else { return nil }
        self.client = client
        self.sourceID = sourceID
        self.name = name
        self.id = Self.makeID(server: config.id, source: sourceID)
    }

    /// `suwayomi.<server uuid>.<source id>` — stable, so library entries and downloads can find the source again.
    static func makeID(server: UUID, source: String) -> String { "suwayomi.\(server.uuidString).\(source)" }

    static func parseID(_ id: String) -> (server: UUID, source: String)? {
        let prefix = "suwayomi."
        guard id.hasPrefix(prefix) else { return nil }
        let rest = id.dropFirst(prefix.count)
        guard rest.count > 37, let server = UUID(uuidString: String(rest.prefix(36))),
              rest[rest.index(rest.startIndex, offsetBy: 36)] == "." else { return nil }
        let source = String(rest.dropFirst(37))
        return source.isEmpty ? nil : (server, source)
    }

    // MARK: Source

    func search(query: String, page: Int) async throws -> [MangaSummary] {
        var input: [String: Any] = ["source": sourceID, "type": query.isEmpty ? "POPULAR" : "SEARCH",
                                    "page": max(page, 1)]
        if !query.isEmpty { input["query"] = query }
        let data: SuwayomiClient.SourceMangaData = try await client.run(
            "mutation($input: FetchSourceMangaInput!) { fetchSourceManga(input: $input) { hasNextPage mangas { id title thumbnailUrl } } }",
            ["input": input])
        return data.fetchSourceManga.mangas.map(summary)
    }

    func details(for manga: MangaSummary) async throws -> MangaDetails {
        let mangaID = try identifier(manga.id)
        let data: SuwayomiClient.MangaDetailData = try await client.run(
            "mutation($input: FetchMangaInput!) { fetchManga(input: $input) { manga { id title thumbnailUrl author artist description } } }",
            ["input": ["id": mangaID]])
        let node = data.fetchManga.manga
        return MangaDetails(title: node.title, coverURL: manga.coverURL,
                            author: node.author ?? node.artist,
                            summary: node.description.flatMap { $0.isEmpty ? nil : $0 })
    }

    func chapters(for manga: MangaSummary) async throws -> [ChapterSummary] {
        let mangaID = try identifier(manga.id)
        let data: SuwayomiClient.ChaptersData = try await client.run(
            "mutation($input: FetchChaptersInput!) { fetchChapters(input: $input) { chapters { id name chapterNumber sourceOrder } } }",
            ["input": ["mangaId": mangaID]])
        return Self.chapterList(from: data.fetchChapters.chapters)
    }

    func pages(for chapter: ChapterSummary) async throws -> [PageSource] {
        let chapterID = try identifier(chapter.id)
        let data: SuwayomiClient.PagesData = try await client.run(
            "mutation($input: FetchChapterPagesInput!) { fetchChapterPages(input: $input) { pages } }",
            ["input": ["chapterId": chapterID]])
        let headers = client.imageHeaders.isEmpty ? nil : client.imageHeaders
        return data.fetchChapterPages.pages.compactMap { path in
            SuwayomiClient.absoluteURL(path, base: client.base).map { PageSource(url: $0.absoluteString, headers: headers) }
        }
    }

    // MARK: Helpers

    private func summary(_ node: SuwayomiClient.MangaNode) -> MangaSummary {
        MangaSummary(id: String(node.id), title: node.title,
                     coverURL: node.thumbnailUrl.flatMap { SuwayomiClient.absoluteURL($0, base: client.base)?.absoluteString })
    }

    private func identifier(_ text: String) throws -> Int {
        guard let value = Int(text) else { throw SuwayomiError.badIdentifier }
        return value
    }

    /// Oldest first. Chapters without a usable number (Suwayomi reports -1) keep the source's order.
    static func chapterList(from nodes: [SuwayomiClient.ChapterNode]) -> [ChapterSummary] {
        nodes.sorted { a, b in
            let an = (a.chapterNumber ?? -1) >= 0 ? a.chapterNumber! : nil
            let bn = (b.chapterNumber ?? -1) >= 0 ? b.chapterNumber! : nil
            if let an, let bn, an != bn { return an < bn }
            return (a.sourceOrder ?? 0) > (b.sourceOrder ?? 0)
        }.map {
            ChapterSummary(id: String($0.id), name: $0.name,
                           number: ($0.chapterNumber ?? -1) >= 0 ? $0.chapterNumber : nil)
        }
    }
}
