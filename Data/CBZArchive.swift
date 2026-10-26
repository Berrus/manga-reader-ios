import Foundation

import ZIPFoundation

enum CBZError: Error { case noImages, unreadable, pageOutOfRange }

actor CBZArchive: PageProvider {

    private let archive: Archive

    private let entries: [Entry]

    nonisolated let pageCount: Int

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "avif", "heic"]

    init(url: URL) throws {

        guard let archive = try? Archive(url: url, accessMode: .read) else { throw CBZError.unreadable }

        let images = archive

            .filter { entry in

                guard entry.type == .file else { return false }

                let name = (entry.path as NSString).lastPathComponent

                if name.hasPrefix(".") || entry.path.contains("__MACOSX") { return false }

                return Self.imageExtensions.contains((name as NSString).pathExtension.lowercased())

            }

            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        guard !images.isEmpty else { throw CBZError.noImages }

        self.archive = archive

        self.entries = images

        self.pageCount = images.count

    }

    func pageData(at index: Int) throws -> Data {

        guard entries.indices.contains(index) else { throw CBZError.pageOutOfRange }

        var data = Data()

        _ = try archive.extract(entries[index]) { data.append($0) }

        return data

    }

}

