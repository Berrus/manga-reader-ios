import Foundation

import SwiftData

@Model

final class Chapter {

    @Attribute(.unique) var id: UUID

    var name: String

    var number: Double

    var fileName: String

    var pageCount: Int

    var lastPage: Int

    var isRead: Bool

    var addedAt: Date

    var manga: Manga?

    init(name: String, number: Double, fileName: String, pageCount: Int) {

        self.id = UUID()

        self.name = name

        self.number = number

        self.fileName = fileName

        self.pageCount = pageCount

        self.lastPage = 0

        self.isRead = false

        self.addedAt = .now

    }

    var fileURL: URL { LibraryImporter.booksDirectory.appendingPathComponent(fileName) }

    var inProgress: Bool { !isRead && lastPage > 0 }

}

