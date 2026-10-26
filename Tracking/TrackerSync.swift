import Foundation
import SwiftData
import OSLog

/// Keeps local reading progress and tracker entries in step. Progress only ever moves forward:
/// the higher chapter number wins, and syncing never marks local chapters unread.
/// Runs on the main actor because the SwiftData models are main-actor bound.
@MainActor
final class TrackerSync {
    static let shared = TrackerSync()

    enum Outcome: Equatable {
        case unchanged
        case pulled(Double)
        case pushed(Double)
    }

    private let log = Logger(subsystem: "FolioReader", category: "tracking")
    private(set) var trackers: [String: any Tracker] = [:]
    private var syncing: Set<UUID> = []

    func register(_ tracker: any Tracker) { trackers[tracker.id] = tracker }
    func unregister(id: String) { trackers[id] = nil }

    /// Compares one link with its remote entry and moves the lagging side forward.
    @discardableResult
    func reconcile(manga: Manga, link: TrackLink, tracker: any Tracker) async throws -> Outcome {
        let remote = try await tracker.fetch(remoteId: link.remoteId)
        let local = manga.lastChapterRead
        let outcome: Outcome

        if remote.chaptersRead > local {
            markRead(manga, upTo: remote.chaptersRead)
            outcome = .pulled(remote.chaptersRead)
        } else if local > remote.chaptersRead {
            var entry = remote
            entry.chaptersRead = local
            if entry.status != .completed { entry.status = .reading }
            try await tracker.push(entry)
            outcome = .pushed(local)
        } else {
            outcome = .unchanged
        }
        link.lastSyncedAt = .now
        return outcome
    }

    /// Call after a chapter is finished. Failures are logged, never shown: syncing is best effort.
    func syncAfterReading(_ manga: Manga) async {
        guard let context = manga.modelContext, !syncing.contains(manga.id) else { return }
        syncing.insert(manga.id)
        defer { syncing.remove(manga.id) }

        let id = manga.id
        let links = (try? context.fetch(FetchDescriptor<TrackLink>(predicate: #Predicate { $0.mangaID == id }))) ?? []
        for link in links {
            guard let tracker = trackers[link.trackerID] else { continue }
            do { try await reconcile(manga: manga, link: link, tracker: tracker) }
            catch { log.error("Sync failed for \(manga.title): \(error.localizedDescription)") }
        }
    }

    /// Call on launch to pick up progress made on other devices.
    func syncAll(context: ModelContext) async {
        guard !trackers.isEmpty,
              let mangas = try? context.fetch(FetchDescriptor<Manga>()) else { return }
        for manga in mangas { await syncAfterReading(manga) }
    }

    /// Marks chapters up to `number` as read. Chapters without a parsed number (0) are skipped
    /// so a remote "read 40" can't mark every oddly named file as read.
    private func markRead(_ manga: Manga, upTo number: Double) {
        for chapter in manga.chapters where chapter.number > 0 && chapter.number <= number && !chapter.isRead {
            chapter.isRead = true
        }
    }
}
