import Foundation
import SwiftData
import CZlib

/// Reads Komikku's gzip-compressed Protocol Buffers library backup and converts its
/// categories and reading progress to Folio's metadata-backup format. No manga files,
/// source extensions, credentials, or tracker-account tokens are imported.
enum KomikkuBackupImporter {
    struct Preview {
        let backup: BackupFile
        let seriesCount: Int
        let chapterCount: Int
    }

    private static let maxFileBytes = 10_000_000
    private static let maxExpandedBytes = 64_000_000
    private static let maxSeries = 20_000
    private static let maxChapters = 200_000

    static func decode(_ data: Data) throws -> Preview {
        guard !data.isEmpty, data.count <= maxFileBytes else { throw KomikkuBackupError.invalidSize }
        let payload = data.starts(with: [0x1f, 0x8b]) ? try gunzip(data) : data
        guard payload.count <= maxExpandedBytes, payload.first != UInt8(ascii: "{") else {
            throw KomikkuBackupError.invalidFormat
        }

        let root = try ProtoReader(payload).fields()
        let savedCategories = root.filter { $0.number == 2 }.compactMap(\.bytes)
        let categories = try savedCategories.map(parseCategory)
        guard categories.count <= 1_000 else { throw KomikkuBackupError.invalidFormat }
        var categoryIDs: [UInt64: UUID] = [:]
        for category in categories where categoryIDs[category.sourceID] == nil {
            categoryIDs[category.sourceID] = category.id
        }

        let mangaMessages = root.filter { $0.number == 1 }.compactMap(\.bytes)
        guard !mangaMessages.isEmpty, mangaMessages.count <= maxSeries else { throw KomikkuBackupError.invalidFormat }

        var series: [BackupFile.SeriesEntry] = []
        var totalChapters = 0
        for bytes in mangaMessages {
            let fields = try ProtoReader(bytes).fields()
            let title = (fields.first { $0.number == 800 }?.string ?? fields.first { $0.number == 3 }?.string)
                .map(validTitle) ?? ""
            guard !title.isEmpty else { continue }

            let savedChapterMessages = fields.filter { $0.number == 16 }.compactMap(\.bytes)
            totalChapters += savedChapterMessages.count
            guard totalChapters <= maxChapters else { throw KomikkuBackupError.invalidFormat }

            var chapters: [BackupFile.ChapterEntry] = []
            chapters.reserveCapacity(savedChapterMessages.count)
            for chapterBytes in savedChapterMessages {
                let chapter = try ProtoReader(chapterBytes).fields()
                guard let name = chapter.first(where: { $0.number == 2 })?.string,
                      !name.isEmpty,
                      let numberBits = chapter.first(where: { $0.number == 9 })?.fixed32 else { continue }
                let number = Double(Float(bitPattern: numberBits))
                guard number.isFinite else { continue }
                let rawLastPage = chapter.first(where: { $0.number == 6 })?.integer ?? 0
                let lastPage = Int(min(rawLastPage, UInt64(Int.max)))
                let isRead = (chapter.first(where: { $0.number == 4 })?.integer ?? 0) != 0
                chapters.append(.init(name: name, number: number, pageCount: 0,
                                      lastPage: max(0, lastPage), isRead: isRead))
            }

            let mangaCategoryIDs = fields.filter { $0.number == 17 }.flatMap(\.integers)
            let categoryID = mangaCategoryIDs.compactMap { categoryIDs[$0] }.first
            series.append(.init(id: UUID(), title: title, direction: "rightToLeft", readerMode: "paged",
                                categoryID: categoryID, lastReadAt: nil, lastReadChapterName: nil,
                                chapters: chapters, sourceID: nil, remoteID: nil, mergeGroupID: nil))
        }

        guard !series.isEmpty else { throw KomikkuBackupError.noUsableEntries }
        var backup = BackupFile()
        backup.categories = categories.map { .init(id: $0.id, name: $0.name, order: $0.order) }
        backup.series = series
        return Preview(backup: backup, seriesCount: series.count,
                       chapterCount: series.reduce(0) { $0 + $1.chapters.count })
    }

    private struct SavedCategory {
        let sourceID: UInt64
        let id: UUID
        let name: String
        let order: Int
    }

    private static func parseCategory(_ data: Data) throws -> SavedCategory {
        let fields = try ProtoReader(data).fields()
        let name = fields.first { $0.number == 1 }?.string ?? ""
        guard !name.isEmpty else { throw KomikkuBackupError.invalidFormat }
        let sourceID = fields.first { $0.number == 3 }?.integer ?? 0
        let orderValue = fields.first { $0.number == 2 }?.integer ?? 0
        let order = Int(min(orderValue, UInt64(Int.max)))
        return SavedCategory(sourceID: sourceID, id: UUID(), name: name, order: order)
    }

    private static func validTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func gunzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        let status = inflateInit2_(&stream, 47, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
        guard status == 0 else { throw KomikkuBackupError.invalidFormat }
        defer { inflateEnd(&stream) }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let result: Bool = data.withUnsafeBytes { rawInput in
            guard let base = rawInput.baseAddress else { return false }
            stream.next_in = UnsafeMutablePointer(mutating: base.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(rawInput.count)
            while true {
                let code = buffer.withUnsafeMutableBufferPointer { rawOutput -> Int32 in
                    stream.next_out = rawOutput.baseAddress
                    stream.avail_out = uInt(rawOutput.count)
                    return inflate(&stream, 0)
                }
                let produced = buffer.count - Int(stream.avail_out)
                output.append(contentsOf: buffer.prefix(produced))
                if output.count > maxExpandedBytes { return false }
                if code == 1 { return true } // Z_STREAM_END
                if code != 0 || (produced == 0 && stream.avail_in == 0) { return false }
            }
        }
        guard result else { throw KomikkuBackupError.invalidFormat }
        return output
    }
}

private struct ProtoField {
    enum Value { case integer(UInt64), bytes(Data), fixed32(UInt32), fixed64(UInt64) }
    let number: Int
    let value: Value

    var bytes: Data? { if case .bytes(let value) = value { return value }; return nil }
    var fixed32: UInt32? { if case .fixed32(let value) = value { return value }; return nil }
    var integer: UInt64? { if case .integer(let value) = value { return value }; return nil }
    var string: String? { bytes.flatMap { String(data: $0, encoding: .utf8) } }

    var integers: [UInt64] {
        if let integer { return [integer] }
        guard let bytes else { return [] }
        return (try? ProtoReader(bytes).packedVarints()) ?? []
    }
}

private struct ProtoReader {
    let data: Data
    init(_ data: Data) { self.data = data }

    func fields() throws -> [ProtoField] {
        var cursor = Cursor(data)
        var result: [ProtoField] = []
        while !cursor.isAtEnd {
            let key = try cursor.varint()
            let number = Int(key >> 3)
            guard number > 0 else { throw KomikkuBackupError.invalidFormat }
            switch key & 7 {
            case 0: result.append(.init(number: number, value: .integer(try cursor.varint())))
            case 1: result.append(.init(number: number, value: .fixed64(try cursor.fixed64())))
            case 2: result.append(.init(number: number, value: .bytes(try cursor.lengthDelimited())))
            case 5: result.append(.init(number: number, value: .fixed32(try cursor.fixed32())))
            default: throw KomikkuBackupError.invalidFormat
            }
            guard result.count <= 500_000 else { throw KomikkuBackupError.invalidFormat }
        }
        return result
    }

    func packedVarints() throws -> [UInt64] {
        var cursor = Cursor(data)
        var values: [UInt64] = []
        while !cursor.isAtEnd {
            values.append(try cursor.varint())
            guard values.count <= 200_000 else { throw KomikkuBackupError.invalidFormat }
        }
        return values
    }
}

private struct Cursor {
    let data: Data
    var offset = 0
    init(_ data: Data) { self.data = data }
    var isAtEnd: Bool { offset == data.count }

    mutating func varint() throws -> UInt64 {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 70, by: 7) {
            guard offset < data.count else { throw KomikkuBackupError.invalidFormat }
            let byte = data[offset]
            offset += 1
            if shift == 63 && byte > 1 { throw KomikkuBackupError.invalidFormat }
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
        }
        throw KomikkuBackupError.invalidFormat
    }

    mutating func lengthDelimited() throws -> Data {
        let count = try varint()
        guard count <= UInt64(data.count - offset) else { throw KomikkuBackupError.invalidFormat }
        defer { offset += Int(count) }
        return data.subdata(in: offset..<(offset + Int(count)))
    }

    mutating func fixed32() throws -> UInt32 {
        guard offset <= data.count - 4 else { throw KomikkuBackupError.invalidFormat }
        defer { offset += 4 }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    mutating func fixed64() throws -> UInt64 {
        guard offset <= data.count - 8 else { throw KomikkuBackupError.invalidFormat }
        defer { offset += 8 }
        return (0..<8).reduce(UInt64(0)) { $0 | UInt64(data[offset + $1]) << ($1 * 8) }
    }
}

enum KomikkuBackupError: LocalizedError {
    case invalidSize, invalidFormat, noUsableEntries
    var errorDescription: String? {
        switch self {
        case .invalidSize: "The backup is empty or exceeds the 10 MB import limit."
        case .invalidFormat: "This file isn't a supported Komikku backup or is damaged."
        case .noUsableEntries: "The backup contains no readable series entries."
        }
    }
}
