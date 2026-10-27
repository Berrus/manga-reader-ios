#if !APP_STORE
import XCTest
@testable import MangaReader

final class ScriptedSourceTests: XCTestCase {
    private func make(_ script: String, hosts: [String] = ["example.com"]) throws -> ScriptedSource {
        let manifest = ScriptedSourceManifest(id: "demo", name: "Demo", version: "1", hosts: hosts,
                                              entry: "https://example.com/demo.js", sha256: ScriptedSource.sha256(script))
        return try ScriptedSource(manifest: manifest, script: script)
    }

    private let script = """
    function search(query, page) { return [{id: "a1", title: query + " " + page, coverURL: "https://cdn.example.com/c.jpg"}]; }
    function details(id) { return {title: "T " + id, summary: "S"}; }
    function chapters(id) { return [{id: "c1", name: "Chapter 1", number: 1}]; }
    function pages(id) { return [{url: "https://cdn.example.com/1.jpg"}, {url: "https://cdn.example.com/2.jpg"}]; }
    """

    func testContractRoundTrip() async throws {
        let source = try make(script)
        XCTAssertEqual(source.id, "js.demo")
        let found = try await source.search(query: "Moon", page: 2)
        XCTAssertEqual(found.map(\.title), ["Moon 2"])
        let details = try await source.details(for: found[0])
        XCTAssertEqual(details.title, "T a1")
        let chapters = try await source.chapters(for: found[0])
        XCTAssertEqual(chapters.first?.name, "Chapter 1")
        let pages = try await source.pages(for: chapters[0])
        XCTAssertEqual(pages.count, 2)
    }

    func testChecksumMismatchIsRefused() {
        let manifest = ScriptedSourceManifest(id: "demo", name: "Demo", version: "1", hosts: ["example.com"],
                                              entry: "https://example.com/demo.js", sha256: String(repeating: "0", count: 64))
        XCTAssertThrowsError(try ScriptedSource(manifest: manifest, script: script))
    }

    func testManifestValidation() {
        func manifest(id: String = "demo", hosts: [String] = ["example.com"], entry: String = "https://example.com/a.js",
                      sha: String = String(repeating: "a", count: 64)) -> ScriptedSourceManifest {
            ScriptedSourceManifest(id: id, name: "N", version: "1", hosts: hosts, entry: entry, sha256: sha)
        }
        XCTAssertNoThrow(try ScriptedSource.validate(manifest()))
        XCTAssertThrowsError(try ScriptedSource.validate(manifest(id: "Bad Id")))
        XCTAssertThrowsError(try ScriptedSource.validate(manifest(hosts: [])))
        XCTAssertThrowsError(try ScriptedSource.validate(manifest(entry: "http://example.com/a.js")))
        XCTAssertThrowsError(try ScriptedSource.validate(manifest(sha: "abc")))
    }

    func testPageOutsideDeclaredHostsIsBlocked() async throws {
        let source = try make("function pages(id) { return [{url: 'https://evil.test/1.jpg'}]; }")
        do {
            _ = try await source.pages(for: ChapterSummary(id: "c", name: "C", number: nil))
            XCTFail("Expected the page address to be blocked")
        } catch { XCTAssertTrue(error is TransportError) }
    }

    func testScriptCannotContactUndeclaredHost() async throws {
        let source = try make("function search(q, p) { return http.get('https://evil.test/x').body; }")
        do {
            _ = try await source.search(query: "x", page: 1)
            XCTFail("Expected the request to be blocked")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Blocked")) }
    }

    func testScriptHasNoFileOrAppAccess() async throws {
        let source = try make("function search(q, p) { return [{id: typeof require + typeof process + typeof fetch + typeof XMLHttpRequest, title: 'x'}]; }")
        let rows = try await source.search(query: "x", page: 1)
        XCTAssertEqual(rows.first?.id, "undefinedundefinedundefinedundefined")
    }

    func testMissingFunctionAndBadReturnAreErrors() async throws {
        let none = try make("var x = 1;")
        do { _ = try await none.search(query: "x", page: 1); XCTFail("Expected an error") } catch {}
        let bad = try make("function search(q, p) { return 'not rows'; }")
        do { _ = try await bad.search(query: "x", page: 1); XCTFail("Expected a decoding error") } catch {}
    }

    func testTooManyItemsAreRefused() async throws {
        let source = try make("function chapters(id) { var r = []; for (var i = 0; i < 1001; i++) r.push({id: 'c' + i, name: 'n'}); return r; }")
        do { _ = try await source.chapters(for: MangaSummary(id: "m", title: "M")); XCTFail("Expected too large") }
        catch { XCTAssertTrue(error is TransportError) }
    }

    func testPolicyFlagMatchesConfiguration() {
        XCTAssertTrue(DistributionPolicy.allowsScriptedSources)
    }
}
#endif

#if APP_STORE
final class ScriptedSourceAppStoreTests: XCTestCase {
    func testScriptedSourcesAreOffInAppStoreBuild() {
        XCTAssertFalse(DistributionPolicy.allowsScriptedSources)
    }
}
#endif
