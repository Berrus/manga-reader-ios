import Foundation

import SwiftData

import UIKit

enum LibraryImporter {

    static var booksDirectory: URL {

        let dir = URL.documentsDirectory.appendingPathComponent("Books", isDirectory: true)

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        return dir

    }

    /// Imports a CBZ as a chapter. Pass `manga` to add to an existing series,

    /// or nil to create a new series from the file name.

    @MainActor

    static func importFile(at sourceURL: URL, into manga: Manga?, context: ModelContext,
                           save: ((ModelContext) throws -> Void)? = nil) async throws {

        let scoped = sourceURL.startAccessingSecurityScopedResource()

        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let fileName = "\(UUID().uuidString).\(sourceURL.pathExtension.lowercased() == "epub" ? "epub" : "cbz")"

        let destination = booksDirectory.appendingPathComponent(fileName)

        try FileManager.default.copyItem(at: sourceURL, to: destination)

        var insertedChapter: Chapter?
        var insertedManga: Manga?
        let oldCover = manga?.coverData
        do {

            let archive = try ComicArchive.open(url: destination)
            let first = try await archive.provider.pageData(at: 0)

            let cover = ImageDownsampler.image(from: first, maxPixel: 500)?

                .jpegData(compressionQuality: 0.8)

            let name = sourceURL.deletingPathExtension().lastPathComponent

            let chapter = Chapter(name: name,

                                  number: guessNumber(from: name),

                                  fileName: fileName,

                                  pageCount: archive.pageCount)

            let target: Manga

            if let manga {

                target = manga

            } else {

                target = Manga(title: name, coverData: cover)

                context.insert(target)
                insertedManga = target

            }

            context.insert(chapter)
            insertedChapter = chapter

            chapter.manga = target

            if target.coverData == nil { target.coverData = cover }

            if let save { try save(context) } else { try context.save() }

        } catch {
            if let insertedChapter { context.delete(insertedChapter) }
            if let insertedManga { context.delete(insertedManga) }
            else { manga?.coverData = oldCover }
            context.processPendingChanges()

            try? FileManager.default.removeItem(at: destination)

            throw error

        }

    }

    /// Uses the last number in the file name, e.g. "Series Vol 3 Ch 12.5" -> 12.5.

    static func guessNumber(from name: String) -> Double {

        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#) else { return 0 }

        let range = NSRange(name.startIndex..., in: name)

        guard let match = regex.matches(in: name, range: range).last,

              let r = Range(match.range, in: name) else { return 0 }

        return Double(name[r]) ?? 0

    }

    static func deleteFiles(for manga: Manga) {

        for chapter in manga.chapters {

            chapter.removeFiles()

        }

    }

}

