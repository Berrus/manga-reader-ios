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

    /// First unread chapter, or the first chapter if everything is read.

    var resumeChapter: Chapter? {

        let sorted = sortedChapters

        return sorted.first(where: { !$0.isRead }) ?? sorted.first

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

