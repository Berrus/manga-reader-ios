import XCTest
@testable import MangaReader

final class ICloudSyncTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testOnlyOtherDevicesNewOrChangedFilesAreMerged() {
        let own = ICloudSync.fileName(device: "me")
        let files: [(name: String, modified: Date)] = [
            (own, t0 + 50),
            ("backup-a.json", t0 + 10),
            ("backup-b.json", t0 + 20),
            ("notes.txt", t0 + 30),
            ("backup-c.json", t0 + 40)
        ]
        let merged = ["backup-a.json": t0 + 10, "backup-b.json": t0 + 5]
        XCTAssertEqual(ICloudSync.filesToMerge(files, ownName: own, merged: merged), ["backup-b.json", "backup-c.json"])
    }

    func testNothingToMergeWhenEverythingIsCurrent() {
        let files: [(name: String, modified: Date)] = [("backup-a.json", t0)]
        XCTAssertTrue(ICloudSync.filesToMerge(files, ownName: "backup-me.json", merged: ["backup-a.json": t0]).isEmpty)
    }

    func testDeviceFileNamesAreStable() {
        XCTAssertEqual(ICloudSync.fileName(device: "123"), "backup-123.json")
    }
}
