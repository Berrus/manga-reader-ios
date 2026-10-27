import Foundation

/// MangaDex through its official public API (https://api.mangadex.org).
/// Excludes erotica/pornographic content. Chapters hosted off-site are skipped.
/// Show "Data from MangaDex" wherever results appear and respect their API terms and rate limits.
struct MangaDexSource: Source {
    let id = "mangadex"
    let name = "MangaDex"
    var accessPolicy: SourceAccessPolicy { SourceAccessPolicy(hosts: ["mangadex.org", "mangadex.network"]) }

    private static let api = URL(string: "https://api.mangadex.org")!
    private static let ratings = ["safe", "suggestive"]
    private static let pageSize = 20

    // MARK: Source

    func search(query: String, page: Int) async throws -> [MangaSummary] {
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(Self.pageSize)),
            .init(name: "offset", value: String(max(page - 1, 0) * Self.pageSize)),
            .init(name: "includes[]", value: "cover_art"),
            .init(name: "availableTranslatedLanguage[]", value: "en")
        ]
        items += Self.ratings.map { URLQueryItem(name: "contentRating[]", value: $0) }
        if query.isEmpty { items.append(.init(name: "order[followedCount]", value: "desc")) }
        else {
            items.append(.init(name: "title", value: query))
            items.append(.init(name: "order[relevance]", value: "desc"))
        }
        let result: List<MangaItem> = try await get("/manga", items)
        return result.data.map {
            MangaSummary(id: $0.id, title: Self.title(from: $0.attributes.title), coverURL: Self.coverURL(for: $0))
        }
    }

    func related(to manga: MangaSummary) async throws -> [MangaSummary] {
        let detail: One<MangaItem> = try await get("/manga/\(manga.id)", [])
        let relatedIDs = Self.relatedIDs(of: detail.data)
        let tagIDs = Self.similarTagIDs(of: detail.data)
        var found: [MangaItem] = []
        if !relatedIDs.isEmpty {
            let query = Self.listingQuery() + relatedIDs.map { URLQueryItem(name: "ids[]", value: $0) }
            found += (try await get("/manga", query) as List<MangaItem>).data
        }
        if !tagIDs.isEmpty {
            found += (try await get("/manga", Self.similarQuery(tagIDs: tagIDs)) as List<MangaItem>).data
        }
        return Self.dedupe(found, excluding: manga.id).map {
            MangaSummary(id: $0.id, title: Self.title(from: $0.attributes.title), coverURL: Self.coverURL(for: $0))
        }
    }

    // MARK: Recommendations (pure, unit tested)

    /// Works the author linked as related (sequels, spin-offs, adaptations), at most 6.
    static func relatedIDs(of item: MangaItem) -> [String] {
        Array(item.relationships.filter { $0.type == "manga" }.compactMap(\.id).prefix(6))
    }

    /// Up to 3 genre/theme tags. Content and format tags are left out so suggestions stay broad and safe.
    static func similarTagIDs(of item: MangaItem) -> [String] {
        Array((item.attributes.tags ?? []).filter { $0.attributes?.group == "genre" || $0.attributes?.group == "theme" }
            .map(\.id).prefix(3))
    }

    private static let suggestionLimit = 12

    static func listingQuery() -> [URLQueryItem] {
        [URLQueryItem(name: "limit", value: String(suggestionLimit)),
         URLQueryItem(name: "includes[]", value: "cover_art")]
            + ratings.map { URLQueryItem(name: "contentRating[]", value: $0) }
    }

    static func similarQuery(tagIDs: [String]) -> [URLQueryItem] {
        listingQuery() + tagIDs.map { URLQueryItem(name: "includedTags[]", value: $0) } + [
            URLQueryItem(name: "includedTagsMode", value: "AND"),
            URLQueryItem(name: "availableTranslatedLanguage[]", value: "en"),
            URLQueryItem(name: "order[followedCount]", value: "desc")]
    }

    /// Keeps first occurrences, drops the title being viewed, caps the list.
    static func dedupe(_ items: [MangaItem], excluding id: String) -> [MangaItem] {
        var seen: Set<String> = [id]
        return Array(items.filter { seen.insert($0.id).inserted }.prefix(suggestionLimit))
    }

    func details(for manga: MangaSummary) async throws -> MangaDetails {
        let result: One<MangaItem> = try await get("/manga/\(manga.id)", [
            .init(name: "includes[]", value: "author"), .init(name: "includes[]", value: "cover_art")
        ])
        let item = result.data
        return MangaDetails(title: Self.title(from: item.attributes.title),
                            coverURL: Self.coverURL(for: item),
                            author: item.relationships.first { $0.type == "author" }?.attributes?.name,
                            summary: item.attributes.description?["en"])
    }

    func chapters(for manga: MangaSummary) async throws -> [ChapterSummary] {
        var all: [ChapterItem] = []
        var offset = 0
        while offset < 2_000 {
            var items: [URLQueryItem] = [
                .init(name: "limit", value: "500"), .init(name: "offset", value: String(offset)),
                .init(name: "translatedLanguage[]", value: "en"),
                .init(name: "order[chapter]", value: "asc")
            ]
            items += Self.ratings.map { URLQueryItem(name: "contentRating[]", value: $0) }
            let page: List<ChapterItem> = try await get("/manga/\(manga.id)/feed", items)
            all += page.data
            offset += page.data.count
            if page.data.isEmpty || offset >= (page.total ?? 0) { break }
        }
        return Self.chapterList(from: all)
    }

    func pages(for chapter: ChapterSummary) async throws -> [PageSource] {
        let server: AtHome = try await get("/at-home/server/\(chapter.id)")
        return server.chapter.data.map {
            PageSource(url: "\(server.baseUrl)/data/\(server.chapter.hash)/\($0)", headers: nil)
        }
    }

    // MARK: Helpers

    static func title(from titles: [String: String]) -> String {
        titles["en"] ?? titles.values.first ?? "Untitled"
    }

    private static func coverURL(for item: MangaItem) -> String? {
        guard let file = item.relationships.first(where: { $0.type == "cover_art" })?.attributes?.fileName else { return nil }
        return "https://uploads.mangadex.org/covers/\(item.id)/\(file).256.jpg"
    }

    /// One entry per chapter number (several groups may upload the same chapter); off-site chapters are dropped.
    static func chapterList(from items: [ChapterItem]) -> [ChapterSummary] {
        var seen = Set<String>()
        var result: [ChapterSummary] = []
        for item in items where item.attributes.externalUrl == nil && (item.attributes.pages ?? 0) > 0 {
            let number = item.attributes.chapter ?? "Oneshot"
            guard seen.insert(number).inserted else { continue }
            let title = item.attributes.title.flatMap { $0.isEmpty ? nil : $0 }
            result.append(ChapterSummary(id: item.id,
                                         name: title.map { "Ch. \(number) – \($0)" } ?? "Chapter \(number)",
                                         number: Double(number)))
        }
        return result
    }

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: Self.api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("FolioReader/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await SourceTransport.load(request, policy: accessPolicy, maxBytes: 10_000_000)
        if response.statusCode == 429 { throw MangaDexError.rateLimited }
        if !(200..<300).contains(response.statusCode) { throw MangaDexError.http(response.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Models

    private struct List<T: Decodable>: Decodable { let data: [T]; let total: Int? }
    private struct One<T: Decodable>: Decodable { let data: T }

    struct MangaItem: Decodable {
        struct Attributes: Decodable {
            struct Tag: Decodable {
                struct Attributes: Decodable { let group: String? }
                let id: String
                let attributes: Attributes?
            }
            let title: [String: String]
            let description: [String: String]?
            let tags: [Tag]?
        }
        struct Relationship: Decodable {
            struct Attributes: Decodable { let fileName: String?; let name: String? }
            let id: String?
            let type: String
            let attributes: Attributes?
        }
        let id: String
        let attributes: Attributes
        let relationships: [Relationship]
    }

    struct ChapterItem: Decodable {
        struct Attributes: Decodable {
            let chapter: String?
            let title: String?
            let pages: Int?
            let externalUrl: String?
        }
        let id: String
        let attributes: Attributes
    }

    private struct AtHome: Decodable {
        struct Chapter: Decodable { let hash: String; let data: [String] }
        let baseUrl: String
        let chapter: Chapter
    }
}

enum MangaDexError: LocalizedError {
    case rateLimited, http(Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited: return "MangaDex is rate limiting requests. Try again in a moment."
        case .http(let code): return "MangaDex returned error \(code)."
        }
    }
}
