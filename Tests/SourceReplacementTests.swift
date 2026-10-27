import XCTest
@testable import MangaReader

final class SourceReplacementTests: XCTestCase {
    private func manifest(hosts: [String] = ["example.com"], version: String = "1") -> JSSourceManifest {
        JSSourceManifest(id: "demo.source", name: "Demo", version: version, hosts: hosts)
    }

    func testSameHostsAndSameRepositoryIsAPlainUpdate() {
        XCTAssertNil(SourceStore.replacementWarning(
            existing: manifest(), existingOrigin: "https://a.example/index.json",
            new: manifest(version: "2"), newOrigin: "https://a.example/index.json"))
    }

    func testChangedDomainsAreCalledOut() throws {
        let warning = try XCTUnwrap(SourceStore.replacementWarning(
            existing: manifest(hosts: ["example.com"]), existingOrigin: "https://a.example/index.json",
            new: manifest(hosts: ["other.org"]), newOrigin: "https://a.example/index.json"))
        XCTAssertTrue(warning.contains("other.org"))
        XCTAssertTrue(warning.contains("example.com"))
    }

    func testDifferentRepositoryIsCalledOutEvenWithSameDomains() throws {
        let warning = try XCTUnwrap(SourceStore.replacementWarning(
            existing: manifest(), existingOrigin: "https://a.example/index.json",
            new: manifest(), newOrigin: "https://b.example/index.json"))
        XCTAssertTrue(warning.contains("different repository"))
    }

    func testSourcesInstalledBeforeOriginsWereRecordedDoNotWarnOnSameDomains() {
        XCTAssertNil(SourceStore.replacementWarning(
            existing: manifest(), existingOrigin: nil,
            new: manifest(version: "2"), newOrigin: "https://a.example/index.json"))
    }

    func testDomainComparisonIgnoresCaseAndOrder() {
        XCTAssertNil(SourceStore.replacementWarning(
            existing: manifest(hosts: ["Example.com", "cdn.example.com"]), existingOrigin: nil,
            new: manifest(hosts: ["cdn.example.com", "example.COM"]), newOrigin: nil))
    }
}
