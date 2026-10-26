import Foundation

import ZIPFoundation

enum CBZError: Error { case noImages, unreadable, pageOutOfRange, pageTooLarge }

actor CBZArchive: PageProvider {
    static let maxPageBytes = 30_000_000

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

        guard UInt64(entries[index].uncompressedSize) <= UInt64(Self.maxPageBytes) else { throw CBZError.pageTooLarge }
        var data = Data()

        _ = try archive.extract(entries[index]) { chunk in
            guard chunk.count <= Self.maxPageBytes - data.count else { throw CBZError.pageTooLarge }
            data.append(chunk)
        }

        return data

    }

}

