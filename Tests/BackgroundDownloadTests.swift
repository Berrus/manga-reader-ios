import XCTest
@testable import MangaReader

final class BackgroundDownloadTests: XCTestCase {
    func testCacheLocationIsStablePerURLAndDifferentAcrossURLs() throws {
        let a = try XCTUnwrap(URL(string: "https://server.example/chapter/1/page/1"))
        let b = try XCTUnwrap(URL(string: "https://server.example/chapter/1/page/2"))
        XCTAssertEqual(BackgroundPageFetcher.cacheURL(for: a), BackgroundPageFetcher.cacheURL(for: a))
        XCTAssertNotEqual(BackgroundPageFetcher.cacheURL(for: a), BackgroundPageFetcher.cacheURL(for: b))
        XCTAssertEqual(BackgroundPageFetcher.cacheURL(for: a).lastPathComponent.count, 64)   // SHA-256 hex
    }

    func testOnlyOldCacheFilesAreStale() {
        let now = Date(timeIntervalSince1970: 100_000)
        let files: [(url: URL, modified: Date)] = [
            (URL(fileURLWithPath: "/old"), now - 25 * 3600),
            (URL(fileURLWithPath: "/fresh"), now - 3600)
        ]
        XCTAssertEqual(BackgroundPageFetcher.staleFiles(files, now: now, maxAge: 24 * 3600).map(\.path), ["/old"])
    }

    func testBackgroundTransfersAreOffUnlessTheUserTurnsThemOn() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: DownloadSettings.backgroundKey)
        defer { defaults.set(saved, forKey: DownloadSettings.backgroundKey) }
        defaults.removeObject(forKey: DownloadSettings.backgroundKey)
        XCTAssertFalse(DownloadSettings.backgroundTransfers)
        defaults.set(true, forKey: DownloadSettings.backgroundKey)
        XCTAssertTrue(DownloadSettings.backgroundTransfers)
    }
}
