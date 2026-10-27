import Foundation

/// MyAnimeList API v2 client. MyAnimeList stores whole chapters, so fractional chapters are rounded
/// down when pushed. Scores are 0...10. Adult titles are excluded by the API's default.
struct MyAnimeListTracker: Tracker {
    let id = "myanimelist"
    let name = "MyAnimeList"
    let auth: MyAnimeListAuth

    private static let api = URL(string: "https://api.myanimelist.net/v2")!

    // MARK: Tracker

    func search(_ title: String) async throws -> [TrackSearchResult] {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else {
            throw TrackerError.server("MyAnimeList needs at least 3 letters to search.")
        }
        let data = try await send("GET", "/manga", query: [
            URLQueryItem(name: "q", value: title), URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "fields", value: "num_chapters")])
        return try Self.results(from: data)
    }

    func fetch(remoteId: Int) async throws -> TrackEntry {
        let data = try await send("GET", "/manga/\(remoteId)", query: [
            URLQueryItem(name: "fields", value: "my_list_status,num_chapters")])
        return try Self.entry(from: data, remoteId: remoteId)
    }

    func push(_ entry: TrackEntry) async throws {
        var form = ["status": Self.malStatus(entry.status),
                    "num_chapters_read": String(Int(entry.chaptersRead.rounded(.down)))]
        if let score = entry.score { form["score"] = String(min(max(Int(score.rounded()), 0), 10)) }
        _ = try await send("PATCH", "/manga/\(entry.remoteId)/my_list_status", form: form)
    }

    // MARK: Parsing and mapping (unit tested)

    static func results(from data: Data) throws -> [TrackSearchResult] {
        struct Page: Decodable {
            struct Item: Decodable {
                struct Node: Decodable {
                    struct Picture: Decodable { let medium: String? }
                    let id: Int
                    let title: String
                    let main_picture: Picture?
                    let num_chapters: Int?
                }
                let node: Node
            }
            let data: [Item]
        }
        return try JSONDecoder().decode(Page.self, from: data).data.map {
            TrackSearchResult(remoteId: $0.node.id, title: $0.node.title,
                              coverURL: $0.node.main_picture?.medium.flatMap(URL.init(string:)),
                              totalChapters: ($0.node.num_chapters ?? 0) > 0 ? $0.node.num_chapters : nil)
        }
    }

    static func entry(from data: Data, remoteId: Int) throws -> TrackEntry {
        struct Manga: Decodable {
            struct Status: Decodable {
                let status: String?
                let score: Int?
                let num_chapters_read: Int?
            }
            let my_list_status: Status?
        }
        guard let status = try JSONDecoder().decode(Manga.self, from: data).my_list_status else {
            return TrackEntry(remoteId: remoteId, chaptersRead: 0, status: .planning)   // not on the user's list yet
        }
        return TrackEntry(remoteId: remoteId, chaptersRead: Double(status.num_chapters_read ?? 0),
                          status: Self.status(from: status.status),
                          score: (status.score ?? 0) > 0 ? Double(status.score ?? 0) : nil)
    }

    static func status(from raw: String?) -> ReadStatus {
        switch raw {
        case "reading": return .reading
        case "completed": return .completed
        case "on_hold": return .onHold
        case "dropped": return .dropped
        default: return .planning
        }
    }

    static func malStatus(_ status: ReadStatus) -> String {
        switch status {
        case .reading: return "reading"
        case .completed: return "completed"
        case .onHold: return "on_hold"
        case .dropped: return "dropped"
        case .planning: return "plan_to_read"
        }
    }

    // MARK: Transport

    private func send(_ method: String, _ path: String, query: [URLQueryItem] = [],
                      form: [String: String]? = nil) async throws -> Data {
        let token = try await auth.validToken()
        var components = URLComponents(url: Self.api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = MyAnimeListAuth.formBody(form)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw TrackerError.unauthorized }
        if status == 429 { throw TrackerError.rateLimited }
        guard (200..<300).contains(status) else { throw TrackerError.server("HTTP \(status)") }
        return data
    }
}
