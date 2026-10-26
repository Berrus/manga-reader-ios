import XCTest
import SwiftData
import UIKit
@testable import MangaReader

@MainActor
final class ReaderEnhancementTests: XCTestCase {
    func testReaderPreferencesBoundMemoryAndMotionInputs() {
        XCTAssertEqual(ReaderTuning.preload(-10), 0)
        XCTAssertEqual(ReaderTuning.preload(100), 4)
        XCTAssertEqual(ReaderTuning.cacheMB(Int.max), 64)
        XCTAssertEqual(ReaderTuning.cacheMB(32), 32)
        XCTAssertEqual(ReaderTuning.speed(.nan), 40)
        XCTAssertEqual(ReaderTuning.speed(-1), 10)
        XCTAssertEqual(ReaderTuning.speed(1000), 100)
    }
    func testMemoryChangesInvalidateOldReaderImages() {
        let chapter = Chapter(name: "Book", number: 1, fileName: "", pageCount: 4)
        let vm = ReaderViewModel(chapter: chapter)
        let revision = vm.imageRevision
        vm.configureMemory(preload: 0, cacheMB: 32)
        XCTAssertEqual(vm.preloadCount, 0)
        XCTAssertEqual(vm.cacheLimitMB, 32)
        XCTAssertGreaterThan(vm.imageRevision, revision)
        let same = vm.imageRevision
        vm.configureMemory(preload: 0, cacheMB: 32)
        XCTAssertEqual(vm.imageRevision, same)
    }
    func testCoverCanvasStaysDarkAndHandlesCorruptImages() {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let tint = CoverReaderTint.extract(data)
        XCTAssertGreaterThan(tint.red, 0)
        XCTAssertLessThanOrEqual(max(tint.red, tint.green, tint.blue), 0.18)
        XCTAssertEqual(CoverReaderTint.extract(Data("bad".utf8)).red, 0)
        XCTAssertEqual(CoverReaderTint.extract(nil).red, 0)
    }
}
