import Foundation

enum TrackerError: LocalizedError {
    case notSignedIn, unauthorized, rateLimited, server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in to AniList."
        case .unauthorized: return "AniList sign-in expired. Reconnect in Settings."
        case .rateLimited: return "AniList is rate limiting requests. Try again shortly."
        case .server(let message): return "AniList error: \(message)"
        }
    }
}

/// AniList GraphQL client. AniList stores progress as whole chapters, so fractional chapters
/// (e.g. 12.5) are rounded down when pushed. Scores here are 0...10.
struct AniListTracker: Tracker {
    let id = "anilist"
    let name = "AniList"
    let tokenProvider: @Sendable () -> String?

    private static let endpoint = URL(string: "https://graphql.anilist.co")!

    // MARK: Tracker

    func search(_ title: String) async throws -> [TrackSearchResult] {
        let query = """
        query ($search: String) {
          Page(perPage: 15) {
            media(search: $search, type: MANGA) {
              id
              title { romaji english }
              coverImage { medium }
              chapters
            }
          }
        }
        """
        let response: SearchData = try await send(query, ["search": title])
        return response.Page.media.map {
            TrackSearchResult(remoteId: $0.id,
                              title: $0.title.english ?? $0.title.romaji ?? "Untitled",
                              coverURL: $0.coverImage?.medium.flatMap(URL.init(string:)),
                              totalChapters: $0.chapters)
        }
    }

    func fetch(remoteId: Int) async throws -> TrackEntry {
        let query = """
        query ($id: Int) {
          Media(id: $id, type: MANGA) {
            id
            mediaListEntry { progress status score(format: POINT_10_DECIMAL) }
          }
        }
        """
        let response: FetchData = try await send(query, ["id": remoteId])
        guard let entry = response.Media.mediaListEntry else {
            return TrackEntry(remoteId: remoteId, chaptersRead: 0, status: .planning)
        }
        return TrackEntry(remoteId: remoteId,
                          chaptersRead: Double(entry.progress ?? 0),
                          status: Self.status(from: entry.status),
                          score: (entry.score ?? 0) > 0 ? entry.score : nil)
    }

    func push(_ entry: TrackEntry) async throws {
        let mutation = """
        mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus, $scoreRaw: Int) {
          SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status, scoreRaw: $scoreRaw) {
            id
          }
        }
        """
        var variables: [String: Any] = [
            "mediaId": entry.remoteId,
            "progress": Int(entry.chaptersRead.rounded(.down)),
            "status": Self.anilistStatus(entry.status)
        ]
        if let score = entry.score { variables["scoreRaw"] = Int((score * 10).rounded()) }
        let _: SaveData = try await send(mutation, variables)
    }

    // MARK: Mapping

    static func status(from raw: String?) -> ReadStatus {
        switch raw {
        case "CURRENT", "REPEATING": return .reading
        case "COMPLETED": return .completed
        case "PAUSED": return .onHold
        case "DROPPED": return .dropped
        default: return .planning
        }
    }

    static func anilistStatus(_ status: ReadStatus) -> String {
        switch status {
        case .reading: return "CURRENT"
        case .completed: return "COMPLETED"
        case .onHold: return "PAUSED"
        case .dropped: return "DROPPED"
        case .planning: return "PLANNING"
        }
    }

    // MARK: Transport

    private func send<T: Decodable>(_ query: String, _ variables: [String: Any]) async throws -> T {
        guard let token = tokenProvider() else { throw TrackerError.notSignedIn }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw TrackerError.unauthorized }
            if http.statusCode == 429 { throw TrackerError.rateLimited }
        }
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if let message = envelope.errors?.first?.message { throw TrackerError.server(message) }
        guard let payload = envelope.data else { throw TrackerError.server("Empty response") }
        return payload
    }

    private struct Envelope<T: Decodable>: Decodable {
        let data: T?
        let errors: [GraphQLError]?
    }
    private struct GraphQLError: Decodable { let message: String }

    private struct SearchData: Decodable {
        struct PageData: Decodable { let media: [Media] }
        struct Media: Decodable {
            struct Title: Decodable { let romaji: String?; let english: String? }
            struct Cover: Decodable { let medium: String? }
            let id: Int
            let title: Title
            let coverImage: Cover?
            let chapters: Int?
        }
        let Page: PageData
    }

    private struct FetchData: Decodable {
        struct MediaNode: Decodable {
            struct ListEntry: Decodable { let progress: Int?; let status: String?; let score: Double? }
            let mediaListEntry: ListEntry?
        }
        let Media: MediaNode
    }

    private struct SaveData: Decodable {}
}
