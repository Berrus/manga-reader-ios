import Foundation

/// Decides which chapters to download after an update check. Pure logic, no side effects.
enum AutoDownloadPolicy {
    /// - Parameters:
    ///   - newChapters: chapters discovered in this update check for `manga`.
    static func candidates(for manga: Manga, scope: AutoDownloadScope, ahead: Int,
                           newChapters: [Chapter]) -> [Chapter] {
        guard manga.isRemote, ahead > 0 else { return [] }
        switch scope {
        case .off:
            return []
        case .reading:
            guard manga.hasStarted else { return [] }
            return nextUnread(manga, ahead)
        case .selected:
            guard manga.autoDownload else { return [] }
            return nextUnread(manga, ahead)
        case .updated:
            return newChapters
                .filter { !$0.isDownloaded && !$0.isRead }
                .sorted { $0.number < $1.number }
                .suffix(ahead)
                .map { $0 }
        }
    }

    /// The next `count` unread chapters, minus the ones already on disk.
    static func nextUnread(_ manga: Manga, _ count: Int) -> [Chapter] {
        manga.sortedChapters
            .filter { !$0.isRead && $0.isRemote }
            .prefix(count)
            .filter { !$0.isDownloaded }
    }
}
