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

    func testInstallThrowsUntilTheReplacementIsConfirmed() {
        let installed = manifest(hosts: ["example.com"])
        let incoming = manifest(hosts: ["other.org"])
        XCTAssertThrowsError(try SourceStore.checkReplacement(
            existing: installed, existingOrigin: nil, new: incoming, newOrigin: "https://x.example/s.json", allow: false)) { error in
            guard case SourceStoreError.replacementNeedsConfirmation(let text) = error else {
                return XCTFail("wrong error \(error)")
            }
            XCTAssertTrue(text.contains("other.org"))
        }
        XCTAssertNoThrow(try SourceStore.checkReplacement(
            existing: installed, existingOrigin: nil, new: incoming, newOrigin: "https://x.example/s.json", allow: true))
    }

    func testFirstInstallAndHarmlessUpdatesNeverThrow() {
        XCTAssertNoThrow(try SourceStore.checkReplacement(
            existing: nil, existingOrigin: nil, new: manifest(), newOrigin: nil, allow: false))
        XCTAssertNoThrow(try SourceStore.checkReplacement(
            existing: manifest(), existingOrigin: "https://a.example/s.json",
            new: manifest(version: "2"), newOrigin: "https://a.example/s.json", allow: false))
    }

    func testDirectInstallFromAnotherAddressIsTreatedLikeAnotherRepository() {
        XCTAssertThrowsError(try SourceStore.checkReplacement(
            existing: manifest(), existingOrigin: "https://a.example/s.json",
            new: manifest(), newOrigin: "https://evil.example/s.json", allow: false))
    }
}
