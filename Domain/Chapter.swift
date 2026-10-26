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
    /// Set for chapters of remote series; pages live in `downloadDirectory` once downloaded.
    var remoteID: String?
    var isDownloaded: Bool = false

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

    var isRemote: Bool { remoteID != nil }

    var downloadDirectory: URL { DownloadStorage.directory.appendingPathComponent(id.uuidString, isDirectory: true) }

    /// Deletes this chapter's files from disk. Safe for both imported CBZs and downloads.
    func removeFiles() {
        if isRemote {
            try? FileManager.default.removeItem(at: downloadDirectory)
            isDownloaded = false
        } else if !fileName.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    var inProgress: Bool { !isRead && lastPage > 0 }

}

