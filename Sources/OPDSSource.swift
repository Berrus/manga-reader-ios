import Foundation

/// OPDS catalogs (Atom feeds) with page streaming, as served by Kavita, Komga and other servers.
/// Point it at a catalog feed (for Kavita, the OPDS URL from your user settings, which includes your key).
/// Entries that link to another feed are series; entries with an OPDS page-streaming link are chapters.
/// Books that can only be downloaded whole (no streaming link) are not shown.
struct OPDSSource: Source {
    let id: String
    let name: String
    private let root: URL
    private let authorization: String?

    var imageHeaders: [String: String] { authorization.map { ["Authorization": $0] } ?? [:] }
    var accessPolicy: SourceAccessPolicy {
        SourceAccessPolicy(hosts: [root.host ?? ""], allowsLocalHTTP: true,
                           port: root.port ?? (root.scheme == "https" ? 443 : 80))
    }

    init?(config: ServerConfig, password: String) {
        guard let url = URL(string: config.url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        id = "opds.\(config.id.uuidString)"
        name = config.name
        root = url
        authorization = config.username.isEmpty && password.isEmpty ? nil
            : "Basic " + Data("\(config.username):\(password)".utf8).base64EncodedString()
        guard accessPolicy.allows(root) else { return nil }
    }

    // MARK: Source

    func search(query: String, page: Int) async throws -> [MangaSummary] {
        guard page <= 1 else { return [] }
        var feed = try await load(root)
        if !query.isEmpty, let template = feed.searchTemplate,
           let url = Self.searchURL(template: template, query: query, base: root) {
            feed = try await load(url)
        }
        let series = feed.entries.filter { $0.streamLink == nil && $0.navigationURL != nil }
        let matches = query.isEmpty || feed.searchTemplate != nil
            ? series : series.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return matches.map { MangaSummary(id: $0.navigationURL!.absoluteString, title: $0.title, coverURL: $0.thumbnailURL?.absoluteString) }
    }

    func details(for manga: MangaSummary) async throws -> MangaDetails {
        let feed = try await load(try seriesURL(manga.id))
        return MangaDetails(title: feed.title.isEmpty ? nil : feed.title, coverURL: manga.coverURL,
                            author: nil, summary: feed.subtitle.isEmpty ? nil : feed.subtitle)
    }

    func chapters(for manga: MangaSummary) async throws -> [ChapterSummary] {
        var result: [ChapterSummary] = []
        var queue: [(URL, Int)] = [(try seriesURL(manga.id), 0)]
        var visited = Set<URL>()
        while !queue.isEmpty, visited.count < 30 {
            let (url, depth) = queue.removeFirst()
            guard visited.insert(url).inserted else { continue }
            let feed = try await load(url)
            for entry in feed.entries {
                if let stream = entry.streamLink, let count = stream.pageCount {
                    result.append(ChapterSummary(id: Self.chapterID(template: stream.href, count: count),
                                                 name: entry.title, number: nil))
                } else if depth < 2, let next = entry.navigationURL {
                    queue.append((next, depth + 1))     // volumes that hold the chapters
                }
            }
            if let next = feed.nextURL { queue.append((next, depth)) }
        }
        return result
    }

    func pages(for chapter: ChapterSummary) async throws -> [PageSource] {
        guard let (template, count) = Self.parseChapterID(chapter.id) else { throw OPDSError.badChapter }
        let headers = imageHeaders.isEmpty ? nil : imageHeaders
        return (0..<count).compactMap { index in
            Self.pageURL(template: template, index: index, base: root).map { PageSource(url: $0.absoluteString, headers: headers) }
        }
    }

    /// Checks that the address serves an OPDS feed.
    func testConnection() async throws -> String {
        let feed = try await load(root)
        guard !feed.entries.isEmpty || !feed.title.isEmpty else { throw OPDSError.notOPDS }
        return feed.title.isEmpty ? "OPDS catalog" : feed.title
    }

    // MARK: Chapter ids and URLs (pure, unit tested)

    /// A chapter id carries its page count and the streaming URL template: "<count>\n<template>".
    static func chapterID(template: String, count: Int) -> String { "\(count)\n\(template)" }

    static func parseChapterID(_ id: String) -> (template: String, count: Int)? {
        guard let split = id.firstIndex(of: "\n"), let count = Int(id[..<split]), count > 0, count <= 5_000 else { return nil }
        return (String(id[id.index(after: split)...]), count)
    }

    /// Streaming templates use `{pageNumber}` (0-based) and sometimes `{maxWidth}`.
    static func pageURL(template: String, index: Int, base: URL) -> URL? {
        let filled = template.replacingOccurrences(of: "{pageNumber}", with: String(index))
            .replacingOccurrences(of: "{maxWidth}", with: "2400")
        return URL(string: filled, relativeTo: base)?.absoluteURL
    }

    static func searchURL(template: String, query: String, base: URL) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: template.replacingOccurrences(of: "{searchTerms}", with: encoded), relativeTo: base)?.absoluteURL
    }

    // MARK: Transport

    private func seriesURL(_ id: String) throws -> URL {
        guard let url = URL(string: id), accessPolicy.allows(url) else { throw TransportError.blocked }
        return url
    }

    private func load(_ url: URL) async throws -> OPDSFeed {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/atom+xml, application/xml;q=0.9", forHTTPHeaderField: "Accept")
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        let data: Data
        do { (data, _) = try await SourceTransport.load(request, policy: accessPolicy, maxBytes: 10_000_000) }
        catch let TransportError.http(code) where code == 401 || code == 403 { throw OPDSError.unauthorized }
        return try OPDSFeed.parse(data, url: url)
    }
}

enum OPDSError: LocalizedError {
    case notOPDS, unauthorized, badChapter

    var errorDescription: String? {
        switch self {
        case .notOPDS: return "That address doesn't look like an OPDS catalog."
        case .unauthorized: return "The server refused the sign-in. Check the username and password, or the key in the address."
        case .badChapter: return "This chapter has no streamable pages."
        }
    }
}

// MARK: - Atom feed

struct OPDSLink: Equatable {
    var rel: String
    var type: String
    var href: String
    var pageCount: Int?
}

struct OPDSEntry {
    var title = ""
    var links: [OPDSLink] = []
    var base: URL

    /// The OPDS page-streaming link (readable page by page).
    var streamLink: OPDSLink? { links.first { $0.rel.contains("opds-pse") } }

    /// A link to another feed (a series, volume or library).
    var navigationURL: URL? {
        links.first { $0.type.contains("atom+xml") && !$0.type.contains("type=entry") && !$0.rel.contains("search") && $0.rel != "self" }
            .flatMap { URL(string: $0.href, relativeTo: base)?.absoluteURL }
    }

    var thumbnailURL: URL? {
        links.first { $0.rel.hasSuffix("/image/thumbnail") || $0.rel.hasSuffix("/image") || $0.rel == "thumbnail" }
            .flatMap { URL(string: $0.href, relativeTo: base)?.absoluteURL }
    }
}

struct OPDSFeed {
    var title = ""
    var subtitle = ""
    var entries: [OPDSEntry] = []
    var links: [OPDSLink] = []
    var base: URL

    var nextURL: URL? {
        links.first { $0.rel == "next" }.flatMap { URL(string: $0.href, relativeTo: base)?.absoluteURL }
    }

    /// The OpenSearch URL template (with `{searchTerms}`), when the catalog offers search.
    var searchTemplate: String? {
        links.first { $0.rel == "search" && $0.href.contains("{searchTerms}") }?.href
    }

    static func parse(_ data: Data, url: URL) throws -> OPDSFeed {
        let parser = XMLParser(data: data)
        let reader = Reader(base: url)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw OPDSError.notOPDS }
        return reader.feed
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var feed: OPDSFeed
        private var path: [String] = []
        private var entry: OPDSEntry?
        private var text = ""

        init(base: URL) { feed = OPDSFeed(base: base) }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributes: [String: String] = [:]) {
            path.append(name)
            text = ""
            if name == "entry" { entry = OPDSEntry(base: feed.base) }
            if name == "link" {
                let link = OPDSLink(rel: attributes["rel"] ?? "", type: attributes["type"] ?? "",
                                    href: attributes["href"] ?? "", pageCount: attributes["pse:count"].flatMap(Int.init))
                if entry != nil { entry?.links.append(link) } else { feed.links.append(link) }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "title" {
                if path == ["feed", "title"] { feed.title = value }
                else if path == ["feed", "entry", "title"] { entry?.title = value }
            } else if name == "subtitle", path == ["feed", "subtitle"] {
                feed.subtitle = value
            } else if name == "entry", let finished = entry {
                feed.entries.append(finished)
                entry = nil
            }
            path.removeLast()
        }
    }
}
