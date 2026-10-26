import Foundation

/// Client for a user-owned Komga server (REST API v1, HTTP basic auth).
struct KomgaSource: Source {
    let id: String
    let name: String
    private let base: URL
    private let authorization: String

    var imageHeaders: [String: String] { ["Authorization": authorization] }
    var accessPolicy: SourceAccessPolicy {
        SourceAccessPolicy(hosts: [base.host ?? ""], allowsLocalHTTP: true, port: base.port ?? (base.scheme == "https" ? 443 : 80))
    }

    init?(config: ServerConfig, password: String) {
        var text = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        self.id = "komga.\(config.id.uuidString)"
        self.name = config.name
        self.base = url
        let credentials = Data("\(config.username):\(password)".utf8).base64EncodedString()
        self.authorization = "Basic \(credentials)"
        guard accessPolicy.allows(base) else { return nil }
    }

    // MARK: Source

    func search(query: String, page: Int) async throws -> [MangaSummary] {
        var items = [URLQueryItem(name: "page", value: String(max(page - 1, 0))),
                     URLQueryItem(name: "size", value: "30"),
                     URLQueryItem(name: "sort", value: "metadata.titleSort,asc")]
        if !query.isEmpty { items.append(URLQueryItem(name: "search", value: query)) }
        let result: Page<Series> = try await get("/api/v1/series", items)
        return result.content.map {
            MangaSummary(id: $0.id, title: $0.metadata?.title ?? $0.name,
                         coverURL: base.appendingPathComponent("api/v1/series/\($0.id)/thumbnail").absoluteString)
        }
    }

    func details(for manga: MangaSummary) async throws -> MangaDetails {
        let series: Series = try await get("/api/v1/series/\(manga.id)")
        let author = series.booksMetadata?.authors?.first { $0.role == "writer" }?.name
            ?? series.booksMetadata?.authors?.first?.name
        let summary = [series.metadata?.summary, series.booksMetadata?.summary]
            .compactMap { $0 }.first { !$0.isEmpty }
        return MangaDetails(title: series.metadata?.title ?? series.name,
                            coverURL: manga.coverURL, author: author, summary: summary)
    }

    func chapters(for manga: MangaSummary) async throws -> [ChapterSummary] {
        let result: Page<Book> = try await get("/api/v1/series/\(manga.id)/books",
                                               [URLQueryItem(name: "unpaged", value: "true"),
                                                URLQueryItem(name: "sort", value: "metadata.numberSort,asc")])
        return result.content.map {
            ChapterSummary(id: $0.id, name: $0.metadata?.title ?? $0.name, number: $0.metadata?.numberSort)
        }
    }

    func pages(for chapter: ChapterSummary) async throws -> [PageSource] {
        let pages: [KomgaPage] = try await get("/api/v1/books/\(chapter.id)/pages")
        return pages.map { page in
            PageSource(url: Self.pageURL(base: base, bookID: chapter.id, page: page).absoluteString,
                       headers: ["Authorization": authorization])
        }
    }

    /// Checks the address and credentials; throws a readable error when they're wrong.
    func testConnection() async throws {
        let _: Empty = try await get("/api/v2/users/me")
    }

    // MARK: Helpers

    static let webSafeTypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp"]

    /// Komga pages are 1-based. Formats iOS can't show are converted by the server.
    static func pageURL(base: URL, bookID: String, page: KomgaPage) -> URL {
        let url = base.appendingPathComponent("api/v1/books/\(bookID)/pages/\(page.number)")
        guard !webSafeTypes.contains(page.mediaType ?? "image/jpeg"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = [URLQueryItem(name: "convert", value: "jpeg")]
        return components.url ?? url
    }

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await SourceTransport.load(request, policy: accessPolicy, maxBytes: 10_000_000)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KomgaError.http(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Models

    private struct Empty: Decodable {}

    private struct Page<T: Decodable>: Decodable { let content: [T] }

    private struct Series: Decodable {
        struct Metadata: Decodable { let title: String?; let summary: String? }
        struct BooksMetadata: Decodable {
            struct Author: Decodable { let name: String; let role: String? }
            let authors: [Author]?
            let summary: String?
        }
        let id: String
        let name: String
        let metadata: Metadata?
        let booksMetadata: BooksMetadata?
    }

    private struct Book: Decodable {
        struct Metadata: Decodable { let title: String?; let numberSort: Double? }
        let id: String
        let name: String
        let metadata: Metadata?
    }
}

struct KomgaPage: Decodable {
    let number: Int
    let mediaType: String?
}

enum KomgaError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(401): return "Wrong username or password."
        case .http(let code): return "The server answered with error \(code)."
        }
    }
}
