#if DEBUG
import SwiftData
import UIKit
import ZIPFoundation

/// Original, generated sample artwork used only by automated UI tests.
/// Normal launches never add sample books or touch the user's library.
@MainActor
enum DemoLibrary {
    static func seed(context: ModelContext) async throws {
        guard ProcessInfo.processInfo.environment["EMPTY_LIBRARY"] != "1" else { return }
        guard try context.fetchCount(FetchDescriptor<Manga>()) == 0 else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (index, title) in ["Moonlit Express", "Garden of Clouds"].enumerated() {
            let url = directory.appendingPathComponent(title + " 01.cbz")
            let archive = try Archive(url: url, accessMode: .create)
            for page in 1...4 {
                let data = artwork(title: title, page: page, garden: index == 1)
                try archive.addEntry(with: "\(page).png", type: .file, uncompressedSize: Int64(data.count)) {
                    position, size in
                    data.subdata(in: Int(position)..<min(Int(position) + size, data.count))
                }
            }
            try await LibraryImporter.importFile(at: url, into: nil, context: context)
            let items = try context.fetch(FetchDescriptor<Manga>())
            if let manga = items.first(where: { $0.title == title + " 01" }) {
                manga.title = title
                manga.chapters.first?.name = "Chapter 1 · The journey begins"
                manga.direction = .leftToRight
                if title == "Moonlit Express" && ProcessInfo.processInfo.environment["UI_TEST_REMOTE_NEXT"] == "1" {
                    manga.sourceID = "unavailable.fixture"
                    manga.remoteID = "fixture-book"
                    let next = Chapter(name: "Online chapter", number: 2, fileName: "", pageCount: 0)
                    next.remoteID = "remote-next"
                    context.insert(next)
                    next.manga = manga
                }
                if ProcessInfo.processInfo.environment["READER_MODE"] == "webtoon" {
                    manga.readerMode = .webtoon
                }
            }
        }
        try context.save()
    }

    static func artwork(title: String, page: Int, garden: Bool) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900), format: format)
        return renderer.pngData { context in
            let cg = context.cgContext
            UIColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
            func text(_ value: String, _ rect: CGRect, _ size: CGFloat, _ color: UIColor) {
                (value as NSString).draw(in: rect, withAttributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: color
                ])
            }
            let ink = UIColor(red: 0.09, green: 0.14, blue: 0.23, alpha: 1)
            text(title.uppercased(), CGRect(x: 28, y: 24, width: 545, height: 48), 32, ink)
            text("AN ORIGINAL SAMPLE COMIC  /  \(page)", CGRect(x: 30, y: 77, width: 540, height: 24), 14, ink)
            for panel in 0...1 {
                let y = CGFloat(123 + panel * 350)
                let rect = CGRect(x: 28, y: y, width: 544, height: 325)
                cg.saveGState()
                cg.addRect(rect)
                cg.clip()
                (garden ? UIColor(red: 0.30, green: 0.55, blue: 0.48, alpha: 1) :
                    UIColor(red: 0.13, green: 0.23, blue: 0.39, alpha: 1)).setFill()
                cg.fill(rect)
                UIColor(red: 0.95, green: 0.76, blue: 0.40, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: 418, y: y + 25, width: 83, height: 83))
                for mountain in 0...3 {
                    let x = CGFloat(mountain * 180 - 100)
                    let peak = y + CGFloat(100 + (mountain % 2) * 45)
                    cg.setFillColor(UIColor(red: 0.20, green: 0.36, blue: 0.42, alpha: 1).cgColor)
                    cg.move(to: CGPoint(x: x, y: y + 325))
                    cg.addLine(to: CGPoint(x: x + 145, y: peak))
                    cg.addLine(to: CGPoint(x: x + 320, y: y + 325))
                    cg.closePath()
                    cg.fillPath()
                }
                if !garden {
                    UIColor(red: 0.90, green: 0.56, blue: 0.30, alpha: 1).setFill()
                    cg.fill(CGRect(x: 82, y: y + 206, width: 376, height: 61))
                    for window in 0..<7 {
                        UIColor(red: 1, green: 0.88, blue: 0.61, alpha: 1).setFill()
                        cg.fill(CGRect(x: CGFloat(98 + window * 48), y: y + 218, width: 29, height: 24))
                    }
                    ink.setFill()
                    cg.fill(CGRect(x: 0, y: y + 282, width: 600, height: 9))
                } else {
                    for flower in 0..<8 {
                        UIColor(red: 0.96, green: 0.73, blue: 0.57, alpha: 1).setFill()
                        cg.fillEllipse(in: CGRect(x: CGFloat(65 + flower * 65), y: y + 230 - CGFloat(flower % 3 * 12),
                                                 width: 34, height: 34))
                    }
                }
                cg.restoreGState()
                ink.setStroke()
                cg.setLineWidth(4)
                cg.stroke(rect)
                let caption = panel == 0 ? "Every journey begins with a little wonder." :
                    "And a new chapter waits beyond the horizon."
                UIColor.white.setFill()
                cg.fill(CGRect(x: 42, y: y + 15, width: 400, height: 47))
                text(caption, CGRect(x: 52, y: y + 24, width: 380, height: 35), 15, ink)
            }
            text("CHAPTER 01  •  PAGE \(page)", CGRect(x: 30, y: 845, width: 540, height: 30), 16, ink)
        }
    }
}
#endif
