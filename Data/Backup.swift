import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Library metadata backup: categories, reading progress and tracker links. It does not contain
/// the comic files themselves; restore matches series by title and chapters by name, so it works
/// after files are re-imported.
struct BackupFile: Codable {
    struct CategoryEntry: Codable { var id: UUID; var name: String; var order: Int }
    struct ChapterEntry: Codable {
        var name: String; var number: Double; var pageCount: Int; var lastPage: Int; var isRead: Bool
    }
    struct SeriesEntry: Codable {
        var id: UUID; var title: String; var direction: String; var readerMode: String
        var categoryID: UUID?; var lastReadAt: Date?; var lastReadChapterName: String?
        var chapters: [ChapterEntry]
    }
    struct LinkEntry: Codable { var mangaID: UUID; var trackerID: String; var remoteId: Int; var remoteTitle: String }

    var version = 1
    var createdAt = Date()
    var categories: [CategoryEntry] = []
    var series: [SeriesEntry] = []
    var trackLinks: [LinkEntry] = []
}

struct RestoreSummary: Equatable {
    var series = 0
    var chapters = 0
    var categories = 0
    var links = 0
}

@MainActor
enum BackupService {
    static func snapshot(context: ModelContext) throws -> BackupFile {
        var file = BackupFile()
        file.categories = try context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.order)]))
            .map { .init(id: $0.id, name: $0.name, order: $0.order) }
        file.series = try context.fetch(FetchDescriptor<Manga>()).map { manga in
            .init(id: manga.id, title: manga.title, direction: manga.directionRaw, readerMode: manga.readerModeRaw,
                  categoryID: manga.categoryID, lastReadAt: manga.lastReadAt,
                  lastReadChapterName: manga.lastReadChapterName,
                  chapters: manga.sortedChapters.map {
                      .init(name: $0.name, number: $0.number, pageCount: $0.pageCount,
                            lastPage: $0.lastPage, isRead: $0.isRead)
                  })
        }
        file.trackLinks = try context.fetch(FetchDescriptor<TrackLink>())
            .map { .init(mangaID: $0.mangaID, trackerID: $0.trackerID, remoteId: $0.remoteId, remoteTitle: $0.remoteTitle) }
        return file
    }

    static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }

    /// Applies progress to series already in the library. Progress only moves forward.
    static func restore(_ file: BackupFile, into context: ModelContext) throws -> RestoreSummary {
        var summary = RestoreSummary()

        // Categories: reuse an existing one with the same name, otherwise create it.
        var categoryMap: [UUID: UUID] = [:]
        let existingCategories = try context.fetch(FetchDescriptor<Category>())
        for entry in file.categories {
            if let match = existingCategories.first(where: { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }) {
                categoryMap[entry.id] = match.id
            } else {
                let category = Category(name: entry.name, order: entry.order)
                context.insert(category)
                categoryMap[entry.id] = category.id
                summary.categories += 1
            }
        }

        var mangaMap: [UUID: Manga] = [:]
        let library = try context.fetch(FetchDescriptor<Manga>())
        for entry in file.series {
            guard let manga = library.first(where: { $0.title.caseInsensitiveCompare(entry.title) == .orderedSame }) else { continue }
            mangaMap[entry.id] = manga
            summary.series += 1
            manga.directionRaw = entry.direction
            manga.readerModeRaw = entry.readerMode
            if let old = entry.categoryID { manga.categoryID = categoryMap[old] }
            if let date = entry.lastReadAt, date > (manga.lastReadAt ?? .distantPast) {
                manga.lastReadAt = date
                manga.lastReadChapterName = entry.lastReadChapterName
            }
            for saved in entry.chapters {
                guard let chapter = manga.chapters.first(where: { $0.name == saved.name }) else { continue }
                let before = (chapter.isRead, chapter.lastPage)
                chapter.isRead = chapter.isRead || saved.isRead
                chapter.lastPage = max(chapter.lastPage, min(saved.lastPage, max(chapter.pageCount - 1, 0)))
                if before != (chapter.isRead, chapter.lastPage) { summary.chapters += 1 }
            }
        }

        let existingLinks = try context.fetch(FetchDescriptor<TrackLink>())
        for link in file.trackLinks {
            guard let manga = mangaMap[link.mangaID],
                  !existingLinks.contains(where: { $0.mangaID == manga.id && $0.trackerID == link.trackerID }) else { continue }
            context.insert(TrackLink(mangaID: manga.id, trackerID: link.trackerID,
                                     remoteId: link.remoteId, remoteTitle: link.remoteTitle))
            summary.links += 1
        }
        try context.save()
        return summary
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
