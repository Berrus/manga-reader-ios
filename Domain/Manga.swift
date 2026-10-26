import Foundation

import SwiftData

enum ReadingDirection: String, Codable, CaseIterable {

    case leftToRight, rightToLeft

}

enum ReaderMode: String, Codable, CaseIterable {

    case paged, webtoon

}

@Model

final class Manga {

    @Attribute(.unique) var id: UUID

    var title: String

    var addedAt: Date

    var directionRaw: String

    var readerModeRaw: String

    @Attribute(.externalStorage) var coverData: Data?

    @Relationship(deleteRule: .cascade, inverse: \Chapter.manga)

    var chapters: [Chapter] = []

    var direction: ReadingDirection {

        get { ReadingDirection(rawValue: directionRaw) ?? .rightToLeft }

        set { directionRaw = newValue.rawValue }

    }

    var readerMode: ReaderMode {

        get { ReaderMode(rawValue: readerModeRaw) ?? .paged }

        set { readerModeRaw = newValue.rawValue }

    }

    var sortedChapters: [Chapter] {

        chapters.sorted { a, b in

            if a.number != b.number { return a.number < b.number }

            return a.name.localizedStandardCompare(b.name) == .orderedAscending

        }

    }

    var unreadCount: Int { chapters.filter { !$0.isRead }.count }

    /// 0...1 share of chapters finished, with the chapter in progress counted partially.
    var progress: Double {
        guard !chapters.isEmpty else { return 0 }
        let total = chapters.reduce(0.0) { sum, chapter in
            if chapter.isRead { return sum + 1 }
            guard chapter.pageCount > 0 else { return sum }
            return sum + Double(chapter.lastPage) / Double(chapter.pageCount)
        }
        return total / Double(chapters.count)
    }

    /// Highest chapter number finished. Numbers are guessed from file names, so this is approximate.
    var lastChapterRead: Double { chapters.filter(\.isRead).map(\.number).max() ?? 0 }

    var hasStarted: Bool { chapters.contains { $0.isRead || $0.lastPage > 0 } }

    /// Resume a partly read chapter before starting an unread one.

    var resumeChapter: Chapter? {

        let sorted = sortedChapters

        return sorted.first(where: { $0.inProgress })
            ?? sorted.first(where: { !$0.isRead })
            ?? sorted.first

    }

    init(title: String, coverData: Data?) {

        self.id = UUID()

        self.title = title

        self.addedAt = .now

        self.directionRaw = ReadingDirection.rightToLeft.rawValue

        self.readerModeRaw = ReaderMode.paged.rawValue

        self.coverData = coverData

    }

}

