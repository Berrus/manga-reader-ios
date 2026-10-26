import Foundation
import Observation
import OSLog
import SwiftData

/// Checks remote series for new chapters, then queues downloads according to the auto-download
/// settings. Runs on launch/foreground (at most every few hours), from "Check now", and as a
/// best-effort background refresh.
@MainActor @Observable
final class LibraryUpdater {
    static let shared = LibraryUpdater()

    struct Summary: Equatable {
        var checked = 0
        var newChapters = 0
        var queued = 0
        var failed = 0
    }

    struct UpdateIssue: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
    private(set) var lastErrors: [UpdateIssue] = []
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var currentTitle: String?
    private(set) var isRunning = false
    private(set) var lastSummary: Summary?
    private let log = Logger(subsystem: "FolioReader", category: "updates")
    nonisolated static let minimumInterval: TimeInterval = 4 * 3600

    /// Runs a check if enough time has passed (or `force`). Returns nil when skipped.
    @discardableResult
    func runIfNeeded(context: ModelContext, force: Bool = false) async -> Summary? {
        if !force, let last = DownloadSettings.lastCheck, Date().timeIntervalSince(last) < Self.minimumInterval {
            return nil
        }
        guard !isRunning, NetworkMonitor.shared.isOnline else { return nil }
        isRunning = true
        lastErrors = []
        completedCount = 0
        totalCount = 0
        defer { isRunning = false; currentTitle = nil }

        var summary = Summary()
        let all = (try? context.fetch(FetchDescriptor<Manga>(predicate: #Predicate { $0.sourceID != nil }))) ?? []
        totalCount = all.count
        var toDownload: [Chapter] = []

        for manga in all {
            if Task.isCancelled { break }
            currentTitle = manga.title
            defer { completedCount += 1 }
            summary.checked += 1
            do {
                let new = try await refresh(manga)
                summary.newChapters += new.count
                toDownload += AutoDownloadPolicy.candidates(for: manga, scope: DownloadSettings.scope,
                                                            ahead: DownloadSettings.ahead, newChapters: new)
            } catch is CancellationError {
                break
            } catch {
                summary.failed += 1
                lastErrors.append(UpdateIssue(title: manga.title, message: error.localizedDescription))
                log.error("Update failed for \(manga.title): \(error.localizedDescription)")
            }
        }

        guard !Task.isCancelled else { return summary }
        if DownloadSettings.deleteRead { deleteReadDownloads(all) }
        do { try context.save() }
        catch {
            summary.failed += 1
            lastErrors.append(UpdateIssue(title: "Library", message: "Couldn't save chapter updates: \(error.localizedDescription)"))
            lastSummary = summary
            return summary
        }
        summary.queued = toDownload.count
        DownloadManager.shared.enqueue(toDownload)
        if summary.failed == 0 { UserDefaults.standard.set(Date(), forKey: DownloadSettings.lastCheckKey) }
        lastSummary = summary
        return summary
    }

    /// Fetches the chapter list for one series and adds any chapters we haven't seen.
    @discardableResult
    func refresh(_ manga: Manga) async throws -> [Chapter] {
        guard let sourceID = manga.sourceID, let remoteID = manga.remoteID,
              let source = SourceRegistry.source(id: sourceID) else { throw DownloadError.sourceUnavailable }
        let remote = try await source.chapters(for: MangaSummary(id: remoteID, title: manga.title, coverURL: nil))
        try Task.checkCancellation()
        var known = Set(manga.chapters.compactMap(\.remoteID))
        var added: [Chapter] = []
        for item in remote where known.insert(item.id).inserted {
            let chapter = Chapter(name: item.name,
                                  number: item.number ?? LibraryImporter.guessNumber(from: item.name),
                                  fileName: "", pageCount: 0)
            chapter.remoteID = item.id
            manga.modelContext?.insert(chapter)
            chapter.manga = manga
            added.append(chapter)
        }
        if !added.isEmpty { manga.lastUpdatedAt = .now }
        return added
    }

    /// Frees space used by chapters you've already read.
    func deleteReadDownloads(_ library: [Manga]) {
        for manga in library {
            for chapter in manga.chapters where chapter.isRemote && chapter.isRead && chapter.isDownloaded {
                chapter.removeFiles()
            }
        }
    }
}
