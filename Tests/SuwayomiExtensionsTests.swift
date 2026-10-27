import XCTest
@testable import MangaReader

final class SuwayomiExtensionsTests: XCTestCase {
    func testVisibleExtensionsHideAdultAndObsoleteAndListInstalledFirst() {
        let list = [
            SuwayomiExtension(pkgName: "z", name: "Zebra"),
            SuwayomiExtension(pkgName: "a", name: "Alpha"),
            SuwayomiExtension(pkgName: "i", name: "Installed", isInstalled: true),
            SuwayomiExtension(pkgName: "n", name: "Adult", isNsfw: true),
            SuwayomiExtension(pkgName: "o", name: "Old", isObsolete: true)
        ]
        XCTAssertEqual(SuwayomiClient.visibleExtensions(list).map(\.pkgName), ["i", "a", "z"])
    }

    func testExtensionPatchSetsOnlyTheRequestedAction() throws {
        let patch = SuwayomiClient.extensionPatch(.uninstall, pkgName: "eu.kanade.tachiyomi.extension.en.demo")
        XCTAssertEqual(patch["id"] as? String, "eu.kanade.tachiyomi.extension.en.demo")
        let inner = try XCTUnwrap(patch["patch"] as? [String: Bool])
        XCTAssertEqual(inner, ["uninstall": true])
        XCTAssertEqual((SuwayomiClient.extensionPatch(.install, pkgName: "p")["patch"] as? [String: Bool]), ["install": true])
        XCTAssertEqual((SuwayomiClient.extensionPatch(.update, pkgName: "p")["patch"] as? [String: Bool]), ["update": true])
    }

    func testRepositoryAddressRules() {
        XCTAssertEqual(SuwayomiClient.normalizedRepository("  https://example.com/index.min.json ", existing: []),
                       "https://example.com/index.min.json")
        XCTAssertNil(SuwayomiClient.normalizedRepository("http://example.com/index.min.json", existing: []))
        XCTAssertNil(SuwayomiClient.normalizedRepository("https://user:pw@example.com/i.json", existing: []))
        XCTAssertNil(SuwayomiClient.normalizedRepository("not a url", existing: []))
        XCTAssertNil(SuwayomiClient.normalizedRepository("https://Example.com/I.json", existing: ["https://example.com/i.json"]),
                     "duplicates are refused regardless of case")
        XCTAssertNil(SuwayomiClient.normalizedRepository("https://example.com/new.json",
                                                         existing: (0..<20).map { "https://example.com/\($0).json" }))
    }

    func testTheDocumentedCommunityRepositoryPassesTheRules() {
        XCTAssertNotNil(SuwayomiClient.normalizedRepository(SuwayomiExtensionsView.keiyoushiRepository, existing: []))
    }

    func testExtensionListDecodesWithMissingFlags() throws {
        let json = Data("""
        {"data":{"fetchExtensions":{"extensions":[
          {"pkgName":"a.b.c","name":"Demo","lang":"en","versionName":"1.4.2","isInstalled":true,"hasUpdate":true,"isObsolete":false,"isNsfw":false},
          {"pkgName":"d.e.f","name":"Bare"}]}}}
        """.utf8)
        let data: SuwayomiClient.FetchExtensionsData = try SuwayomiClient.decode(json)
        XCTAssertEqual(data.fetchExtensions.extensions.count, 2)
        XCTAssertTrue(data.fetchExtensions.extensions[0].hasUpdate)
        XCTAssertFalse(data.fetchExtensions.extensions[1].isInstalled)
        XCTAssertEqual(data.fetchExtensions.extensions[1].lang, "")
    }

    func testRepositoriesAndUpdateResponsesDecode() throws {
        let repos: SuwayomiClient.SettingsData = try SuwayomiClient.decode(
            Data(#"{"data":{"settings":{"extensionRepos":["https://a.example/i.json"]}}}"#.utf8))
        XCTAssertEqual(repos.settings.extensionRepos, ["https://a.example/i.json"])
        let none: SuwayomiClient.SettingsData = try SuwayomiClient.decode(Data(#"{"data":{"settings":{}}}"#.utf8))
        XCTAssertNil(none.settings.extensionRepos)
        let updated: SuwayomiClient.UpdateExtensionData = try SuwayomiClient.decode(
            Data(#"{"data":{"updateExtension":{"extension":{"pkgName":"a.b.c","isInstalled":true}}}}"#.utf8))
        XCTAssertEqual(updated.updateExtension.item?.pkgName, "a.b.c")
    }

    func testExtensionManagementIsOnlyOfferedWherePublicSourcesAre() {
        XCTAssertEqual(DistributionPolicy.allowsExtensionManagement,
                       DistributionPolicy.allowsSuwayomi && DistributionPolicy.allowsPublicSources)
    }
}
