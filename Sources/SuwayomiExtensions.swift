import Foundation

/// An extension (a Tachiyomi/Mihon-style source plugin) on a Suwayomi server. These are Android
/// packages and run on the server, never on this device.
struct SuwayomiExtension: Decodable, Identifiable, Hashable {
    let pkgName: String
    let name: String
    let lang: String
    let versionName: String
    let isInstalled: Bool
    let hasUpdate: Bool
    let isObsolete: Bool
    let isNsfw: Bool

    var id: String { pkgName }

    private enum CodingKeys: String, CodingKey {
        case pkgName, name, lang, versionName, isInstalled, hasUpdate, isObsolete, isNsfw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pkgName = try c.decode(String.self, forKey: .pkgName)
        name = try c.decode(String.self, forKey: .name)
        lang = (try? c.decode(String.self, forKey: .lang)) ?? ""
        versionName = (try? c.decode(String.self, forKey: .versionName)) ?? ""
        isInstalled = (try? c.decode(Bool.self, forKey: .isInstalled)) ?? false
        hasUpdate = (try? c.decode(Bool.self, forKey: .hasUpdate)) ?? false
        isObsolete = (try? c.decode(Bool.self, forKey: .isObsolete)) ?? false
        isNsfw = (try? c.decode(Bool.self, forKey: .isNsfw)) ?? false
    }

    init(pkgName: String, name: String, lang: String = "en", versionName: String = "1",
         isInstalled: Bool = false, hasUpdate: Bool = false, isObsolete: Bool = false, isNsfw: Bool = false) {
        self.pkgName = pkgName; self.name = name; self.lang = lang; self.versionName = versionName
        self.isInstalled = isInstalled; self.hasUpdate = hasUpdate; self.isObsolete = isObsolete; self.isNsfw = isNsfw
    }
}

enum SuwayomiExtensionAction: String {
    case install, update, uninstall
}

extension SuwayomiClient {
    // MARK: Repositories (stored in the server's settings)

    func extensionRepositories() async throws -> [String] {
        let data: SettingsData = try await run("{ settings { extensionRepos } }")
        return data.settings.extensionRepos ?? []
    }

    func setExtensionRepositories(_ repositories: [String]) async throws {
        let _: SetSettingsData = try await run(
            "mutation($input: SetSettingsInput!) { setSettings(input: $input) { settings { extensionRepos } } }",
            ["input": ["settings": ["extensionRepos": repositories]]])
    }

    // MARK: Extensions

    /// Refreshes the extension list from every repository on the server, then returns it.
    func fetchExtensions() async throws -> [SuwayomiExtension] {
        let data: FetchExtensionsData = try await run(
            "mutation { fetchExtensions(input: {}) { extensions { pkgName name lang versionName isInstalled hasUpdate isObsolete isNsfw } } }")
        return Self.visibleExtensions(data.fetchExtensions.extensions)
    }

    func apply(_ action: SuwayomiExtensionAction, to pkgName: String) async throws {
        let _: UpdateExtensionData = try await run(
            "mutation($input: UpdateExtensionInput!) { updateExtension(input: $input) { extension { pkgName isInstalled hasUpdate } } }",
            ["input": Self.extensionPatch(action, pkgName: pkgName)])
    }

    // MARK: Pure helpers (unit tested)

    /// Adult-only and obsolete extensions are left out, matching the rest of the app.
    /// Installed ones first, then by name.
    static func visibleExtensions(_ all: [SuwayomiExtension]) -> [SuwayomiExtension] {
        all.filter { !$0.isNsfw && !$0.isObsolete }.sorted {
            if $0.isInstalled != $1.isInstalled { return $0.isInstalled }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func extensionPatch(_ action: SuwayomiExtensionAction, pkgName: String) -> [String: Any] {
        ["id": pkgName, "patch": [action.rawValue: true]]
    }

    /// A repository address the server may be given: https only, no credentials, no duplicate, at most 20.
    static func normalizedRepository(_ text: String, existing: [String]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 2048, let url = URL(string: trimmed), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, existing.count < 20,
              !existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return nil }
        return trimmed
    }

    // MARK: Response models

    struct SettingsData: Decodable {
        struct Settings: Decodable { let extensionRepos: [String]? }
        let settings: Settings
    }

    struct SetSettingsData: Decodable {
        struct Payload: Decodable {
            struct Settings: Decodable { let extensionRepos: [String]? }
            let settings: Settings
        }
        let setSettings: Payload
    }

    struct FetchExtensionsData: Decodable {
        struct Payload: Decodable { let extensions: [SuwayomiExtension] }
        let fetchExtensions: Payload
    }

    struct UpdateExtensionData: Decodable {
        struct Payload: Decodable {
            struct Item: Decodable { let pkgName: String; let isInstalled: Bool?; let hasUpdate: Bool? }
            let item: Item?
            private enum CodingKeys: String, CodingKey { case item = "extension" }
        }
        let updateExtension: Payload
    }
}
