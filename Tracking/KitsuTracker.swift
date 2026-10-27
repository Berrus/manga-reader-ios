import Foundation

/// Kitsu API (JSON:API). Kitsu stores whole chapters, so 12.5 is sent as 12. Scores are 0...10
/// (Kitsu keeps them as 2...20 in steps of 2).
struct KitsuTracker: Tracker {
    let id = "kitsu"
    let name = "Kitsu"
    let auth: KitsuAuth

    private static let api = URL(string: "https://kitsu.io/api/edge")!

    // MARK: Tracker

    func search(_ title: String) async throws -> [TrackSearchResult] {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let data = try await send("GET", "/manga", query: [
            URLQueryItem(name: "filter[text]", value: title), URLQueryItem(name: "page[limit]", value: "15")])
        return try Self.results(from: data)
    }

    func fetch(remoteId: Int) async throws -> TrackEntry {
        try await findEntry(mangaID: remoteId).entry
    }

    func push(_ entry: TrackEntry) async throws {
        let existing = try await findEntry(mangaID: entry.remoteId)
        let userID = try await requireUserID()
        if let entryID = existing.entryID {
            _ = try await send("PATCH", "/library-entries/\(entryID)",
                               body: Self.updateBody(entryID: entryID, entry: entry))
        } else {
            _ = try await send("POST", "/library-entries", body: Self.createBody(userID: userID, entry: entry))
        }
    }

    // MARK: Parsing and bodies (unit tested)

    static func results(from data: Data) throws -> [TrackSearchResult] {
        struct Page: Decodable {
            struct Item: Decodable {
                struct Attributes: Decodable {
                    struct Poster: Decodable { let small: String? }
                    let canonicalTitle: String?
                    let chapterCount: Int?
                    let posterImage: Poster?
                }
                let id: String
                let attributes: Attributes
            }
            let data: [Item]
        }
        return try JSONDecoder().decode(Page.self, from: data).data.compactMap { item in
            guard let id = Int(item.id) else { return nil }
            return TrackSearchResult(remoteId: id, title: item.attributes.canonicalTitle ?? "Untitled",
                                     coverURL: item.attributes.posterImage?.small.flatMap(URL.init(string:)),
                                     totalChapters: (item.attributes.chapterCount ?? 0) > 0 ? item.attributes.chapterCount : nil)
        }
    }

    /// The user's library entry for a manga: its id (nil when not on the list yet) and the progress on it.
    static func entry(from data: Data, remoteId: Int) throws -> (entryID: String?, entry: TrackEntry) {
        struct List: Decodable {
            struct Item: Decodable {
                struct Attributes: Decodable { let status: String?; let progress: Int?; let ratingTwenty: Int? }
                let id: String
                let attributes: Attributes
            }
            let data: [Item]
        }
        guard let item = try JSONDecoder().decode(List.self, from: data).data.first else {
            return (nil, TrackEntry(remoteId: remoteId, chaptersRead: 0, status: .planning))
        }
        let rating = item.attributes.ratingTwenty ?? 0
        return (item.id, TrackEntry(remoteId: remoteId, chaptersRead: Double(item.attributes.progress ?? 0),
                                    status: status(from: item.attributes.status),
                                    score: rating > 0 ? Double(rating) / 2 : nil))
    }

    static func status(from raw: String?) -> ReadStatus {
        switch raw {
        case "current": return .reading
        case "completed": return .completed
        case "on_hold": return .onHold
        case "dropped": return .dropped
        default: return .planning
        }
    }

    static func kitsuStatus(_ status: ReadStatus) -> String {
        switch status {
        case .reading: return "current"
        case .completed: return "completed"
        case .onHold: return "on_hold"
        case .dropped: return "dropped"
        case .planning: return "planned"
        }
    }

    private static func attributes(for entry: TrackEntry) -> [String: Any] {
        var attributes: [String: Any] = ["status": kitsuStatus(entry.status),
                                         "progress": Int(entry.chaptersRead.rounded(.down))]
        if let score = entry.score { attributes["ratingTwenty"] = min(max(Int((score * 2).rounded()), 2), 20) }
        return attributes
    }

    static func createBody(userID: String, entry: TrackEntry) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["data": [
            "type": "libraryEntries",
            "attributes": attributes(for: entry),
            "relationships": [
                "user": ["data": ["type": "users", "id": userID]],
                "media": ["data": ["type": "manga", "id": String(entry.remoteId)]]
            ]
        ]])
    }

    static func updateBody(entryID: String, entry: TrackEntry) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["data": [
            "id": entryID, "type": "libraryEntries", "attributes": attributes(for: entry)
        ]])
    }

    // MARK: Transport

    private func requireUserID() async throws -> String {
        guard let id = await auth.userID else { throw TrackerError.notSignedIn }
        return id
    }

    private func findEntry(mangaID: Int) async throws -> (entryID: String?, entry: TrackEntry) {
        let userID = try await requireUserID()
        let data = try await send("GET", "/library-entries", query: [
            URLQueryItem(name: "filter[userId]", value: userID), URLQueryItem(name: "filter[kind]", value: "manga"),
            URLQueryItem(name: "filter[mangaId]", value: String(mangaID))])
        return try Self.entry(from: data, remoteId: mangaID)
    }

    private func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        let token = try await auth.validToken()
        var components = URLComponents(url: Self.api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw TrackerError.unauthorized }
        if status == 429 { throw TrackerError.rateLimited }
        guard (200..<300).contains(status) else { throw TrackerError.server("HTTP \(status)") }
        return data
    }
}
