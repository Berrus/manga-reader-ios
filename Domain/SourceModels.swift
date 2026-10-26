import Foundation

struct MangaSummary: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var coverURL: String?
}

struct MangaDetails: Codable, Hashable {
    var title: String?
    var coverURL: String?
    var author: String?
    var summary: String?
}

struct ChapterSummary: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var number: Double?
}

struct PageSource: Codable, Hashable {
    var url: String
    var headers: [String: String]?
}

protocol Source: Sendable {
    var id: String { get }
    var name: String { get }
    func search(query: String, page: Int) async throws -> [MangaSummary]
    func details(for manga: MangaSummary) async throws -> MangaDetails
    func chapters(for manga: MangaSummary) async throws -> [ChapterSummary]
    func pages(for chapter: ChapterSummary) async throws -> [PageSource]
    /// Headers needed to load cover images (e.g. server authentication).
    var imageHeaders: [String: String] { get }
}

extension Source {
    var imageHeaders: [String: String] { [:] }
}
