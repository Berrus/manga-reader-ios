import Foundation
import SwiftData

enum ReadStatus: String, Codable, CaseIterable {
    case planning, reading, completed, onHold, dropped
}

struct TrackSearchResult: Identifiable, Hashable {
    var remoteId: Int
    var title: String
    var coverURL: URL?
    var totalChapters: Int?
    var id: Int { remoteId }
}

struct TrackEntry: Hashable {
    var remoteId: Int
    var chaptersRead: Double
    var status: ReadStatus
    var score: Double?
}

protocol Tracker: Sendable {
    var id: String { get }
    var name: String { get }
    func search(_ title: String) async throws -> [TrackSearchResult]
    func fetch(remoteId: Int) async throws -> TrackEntry
    func push(_ entry: TrackEntry) async throws
}

/// Links a library series to its entry on a tracking service.
@Model
final class TrackLink {
    var mangaID: UUID
    var trackerID: String
    var remoteId: Int
    var remoteTitle: String
    var lastSyncedAt: Date?

    init(mangaID: UUID, trackerID: String, remoteId: Int, remoteTitle: String) {
        self.mangaID = mangaID
        self.trackerID = trackerID
        self.remoteId = remoteId
        self.remoteTitle = remoteTitle
    }
}
