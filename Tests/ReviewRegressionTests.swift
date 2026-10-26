import XCTest
import SwiftData
import UIKit
import ZIPFoundation
@testable import MangaReader

private final class StubProtocol: URLProtocol {
    static var respond: ((URLRequest, StubProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.respond?(request, self) }
    override func stopLoading() {}
    func reply(_ data: Data, length: Int? = nil) {
        var headers: [String: String] = [:]
        if let length { headers["Content-Length"] = String(length) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class SourceSafetyTests: XCTestCase {
    private let policy = SourceAccessPolicy(hosts: ["example.com"])
    private func config() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return config
    }
    func testRejectsExecutableManifestWithoutEvaluatingIt() {
        let manifest = JSSourceManifest(id: "unsafe", name: "Unsafe", version: "1",
                                        hosts: ["example.com"], script: "while (true) {}")
        XCTAssertThrowsError(try SourceStore.validate(manifest))
    }
    func testSourcePolicyRejectsUndeclaredImageHostsAndDowngrades() {
        XCTAssertTrue(policy.allows(URL(string: "https://images.example.com/page.jpg")!))
        XCTAssertFalse(policy.allows(URL(string: "https://example.com.evil.test/page.jpg")!))
        XCTAssertFalse(policy.allows(URL(string: "https://evil.test/cover.jpg")!))
        XCTAssertFalse(policy.allows(URL(string: "http://example.com/page.jpg")!))
        XCTAssertFalse(policy.allows(URL(string: "https://user:pass@example.com/page.jpg")!))
    }
    func testLocalServerPolicyDoesNotPermitPublicPlainHTTPOrPortChanges() {
        let policy = SourceAccessPolicy(hosts: ["192.168.1.5"], allowsLocalHTTP: true, port: 25600)
        XCTAssertTrue(policy.allows(URL(string: "http://192.168.1.5:25600/page")!))
        XCTAssertFalse(policy.allows(URL(string: "http://192.168.1.5:8080/page")!))
        let publicServer = SourceAccessPolicy(hosts: ["example.com"], allowsLocalHTTP: true)
        XCTAssertFalse(publicServer.allows(URL(string: "http://example.com/page")!))
    }
    func testBlockedRequestNeverStartsNetwork() async {
        StubProtocol.respond = { _, _ in XCTFail("A blocked host reached the network") }
        do {
            _ = try await SourceTransport.load(URLRequest(url: URL(string: "https://evil.test/a")!),
                                                policy: policy, maxBytes: 10, configuration: config())
            XCTFail("Expected host rejection")
        } catch { XCTAssertTrue(error is TransportError) }
    }
    func testRedirectCannotEscapeAllowedHosts() async {
        StubProtocol.respond = { request, stub in
            let response = HTTPURLResponse(url: request.url!, statusCode: 302,
                                           httpVersion: nil, headerFields: ["Location": "https://evil.test/a"])!
            stub.client?.urlProtocol(stub, wasRedirectedTo: URLRequest(url: URL(string: "https://evil.test/a")!),
                                    redirectResponse: response)
        }
        do {
            _ = try await SourceTransport.load(URLRequest(url: URL(string: "https://example.com/a")!),
                                               policy: policy, maxBytes: 20, configuration: config())
            XCTFail("Expected redirect rejection")
        } catch { XCTAssertTrue(error is TransportError) }
    }
    func testStreamingLimitRejectsBodyWithoutContentLength() async {
        StubProtocol.respond = { _, stub in stub.reply(Data(repeating: 1, count: 32)) }
        do {
            _ = try await SourceTransport.load(URLRequest(url: URL(string: "https://example.com/a")!),
                                               policy: policy, maxBytes: 8, configuration: config())
            XCTFail("Expected byte limit")
        } catch {
            guard case TransportError.tooLarge = error else { return XCTFail("Wrong error: \(error)") }
        }
    }
    func testAdvertisedOversizeIsRejectedBeforeDecoding() async {
        StubProtocol.respond = { _, stub in stub.reply(Data(), length: 1000) }
        do {
            _ = try await SourceTransport.load(URLRequest(url: URL(string: "https://example.com/a")!),
                                               policy: policy, maxBytes: 8, configuration: config())
            XCTFail("Expected byte limit")
        } catch { XCTAssertTrue(error is TransportError) }
    }
    func testAllowedSmallResponseIsDelivered() async throws {
        StubProtocol.respond = { _, stub in stub.reply(Data("ok".utf8)) }
        let (data, _) = try await SourceTransport.load(URLRequest(url: URL(string: "https://example.com/a")!),
                                                      policy: policy, maxBytes: 8, configuration: config())
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
    }
    func testDeclarativeFieldSelectionHasNoEvaluation() {
        let object: [String: Any] = ["data": [["name": "Book"]]]
        XCTAssertEqual(JSSource.value(at: "data.0.name", in: object) as? String, "Book")
        XCTAssertNil(JSSource.value(at: "data.99.name", in: object))
        XCTAssertNil(JSSource.value(at: "while(true){}", in: object))
    }
}

@MainActor
final class StorageRegressionTests: XCTestCase {
    private func context() throws -> ModelContext {
        let schema = Schema([Manga.self, Chapter.self, TrackLink.self, Category.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ]).mainContext
    }
    private func book(_ title: String, page: Int, context: ModelContext) -> Manga {
        let manga = Manga(title: title, coverData: nil)
        context.insert(manga)
        let chapter = Chapter(name: "Chapter 1", number: 1, fileName: UUID().uuidString, pageCount: 10)
        chapter.lastPage = page
        context.insert(chapter)
        chapter.manga = manga
        return manga
    }
    private func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).pngData { _ in
            UIColor.red.setFill(); UIBezierPath(rect: CGRect(x: 0, y: 0, width: 16, height: 16)).fill()
        }
    }
    func testSameTitleRestoreUsesOriginalIdentities() throws {
        let context = try self.context()
        let a = book("Same title", page: 2, context: context)
        let b = book("Same title", page: 8, context: context)
        let backup = try BackupService.snapshot(context: context)
        a.chapters[0].lastPage = 0; b.chapters[0].lastPage = 0
        _ = try BackupService.restore(backup, into: context)
        XCTAssertEqual(a.chapters[0].lastPage, 2)
        XCTAssertEqual(b.chapters[0].lastPage, 8)
    }
    func testAmbiguousReimportsAreSkippedRatherThanCorrupted() throws {
        let source = try context()
        _ = book("Same title", page: 2, context: source)
        _ = book("Same title", page: 8, context: source)
        let backup = try BackupService.snapshot(context: source)
        let target = try context()
        let a = book("Same title", page: 0, context: target)
        let b = book("Same title", page: 0, context: target)
        let summary = try BackupService.restore(backup, into: target)
        XCTAssertEqual(summary.ambiguous, 2)
        XCTAssertEqual(a.chapters[0].lastPage, 0)
        XCTAssertEqual(b.chapters[0].lastPage, 0)
    }
    func testRemoteIdentitySurvivesTitleAndLocalIDChanges() throws {
        let source = try context()
        let old = book("Old title", page: 6, context: source)
        old.sourceID = "mangadex"; old.remoteID = "remote-book"
        let backup = try BackupService.snapshot(context: source)
        let target = try context()
        let new = book("New title", page: 0, context: target)
        new.sourceID = "mangadex"; new.remoteID = "remote-book"
        _ = try BackupService.restore(backup, into: target)
        XCTAssertEqual(new.chapters[0].lastPage, 6)
    }
    func testFailedSaveRemovesImportModelsWithoutRollingBackUnrelatedChanges() async throws {
        let context = try self.context()
        let existing = book("Existing", page: 3, context: context)
        try context.save()
        existing.title = "An unrelated edit"
        let originalCover = png()
        existing.coverData = originalCover
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".cbz")
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .create)
        let data = png()
        try archive.addEntry(with: "1.png", type: .file, uncompressedSize: Int64(data.count)) { position, count in
            data.subdata(in: Int(position)..<min(data.count, Int(position) + count))
        }
        struct SaveFailure: Error {}
        do {
            try await LibraryImporter.importFile(at: url, into: existing, context: context,
                                                  save: { _ in throw SaveFailure() })
            XCTFail("Expected save failure")
        } catch is SaveFailure {}
        try context.save()
        XCTAssertEqual(existing.title, "An unrelated edit")
        XCTAssertEqual(existing.coverData, originalCover)
        XCTAssertEqual(existing.chapters.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Chapter>()), 1)
    }
    func testOversizedArchiveEntryIsRejectedBeforeExtraction() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".cbz")
        defer { try? FileManager.default.removeItem(at: url) }
        let zip = try Archive(url: url, accessMode: .create)
        try zip.addEntry(with: "1.png", type: .file, uncompressedSize: Int64(CBZArchive.maxPageBytes + 1),
                         compressionMethod: .deflate) { _, count in Data(repeating: 0, count: count) }
        let archive = try CBZArchive(url: url)
        do { _ = try await archive.pageData(at: 0); XCTFail("Expected page limit") }
        catch {
            guard case CBZError.pageTooLarge = error else { return XCTFail("Wrong error: \(error)") }
        }
    }
    func testViewportResizeInvalidatesDecodedImage() async throws {
        let chapter = Chapter(name: "Page", number: 1, fileName: UUID().uuidString + ".cbz", pageCount: 1)
        let data = png()
        let zip = try Archive(url: chapter.fileURL, accessMode: .create)
        defer { try? FileManager.default.removeItem(at: chapter.fileURL) }
        try zip.addEntry(with: "1.png", type: .file, uncompressedSize: Int64(data.count)) { position, count in
            data.subdata(in: Int(position)..<min(data.count, Int(position) + count))
        }
        let vm = ReaderViewModel(chapter: chapter)
        vm.configureViewport(CGSize(width: 300, height: 500), scale: 2)
        let first = await vm.image(at: 0, fit: .screen)
        let revision = vm.imageRevision
        vm.configureViewport(CGSize(width: 800, height: 1100), scale: 2)
        XCTAssertGreaterThan(vm.imageRevision, revision)
        let second = await vm.image(at: 0, fit: .screen)
        XCTAssertNotNil(first); XCTAssertNotNil(second)
        XCTAssertFalse(first === second)
    }
}
