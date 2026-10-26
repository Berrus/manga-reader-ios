import Foundation

/// Which series are downloaded automatically after an update check.
enum AutoDownloadScope: String, CaseIterable, Identifiable {
    case off
    case reading    // series you've started and haven't finished
    case selected   // series where "Auto-download" is switched on
    case updated    // chapters that just appeared, for any series in the library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .reading: return "Series I'm reading"
        case .selected: return "Selected series only"
        case .updated: return "Recently updated"
        }
    }

    var detail: String {
        switch self {
        case .off: return "Nothing is downloaded automatically."
        case .reading: return "Keeps the next unread chapters of series you've started downloaded."
        case .selected: return "Keeps the next unread chapters downloaded for series with Auto-download turned on."
        case .updated: return "Downloads new chapters as they appear, for every series in your library."
        }
    }
}

enum DownloadSettings {
    static let scopeKey = "download.scope"
    static let aheadKey = "download.ahead"
    static let wifiOnlyKey = "download.wifiOnly"
    static let deleteReadKey = "download.deleteRead"
    static let lastCheckKey = "download.lastCheck"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            scopeKey: AutoDownloadScope.off.rawValue,
            aheadKey: 3,
            wifiOnlyKey: true,
            deleteReadKey: false
        ])
    }

    static var scope: AutoDownloadScope {
        AutoDownloadScope(rawValue: UserDefaults.standard.string(forKey: scopeKey) ?? "") ?? .off
    }
    static var ahead: Int { max(UserDefaults.standard.integer(forKey: aheadKey), 1) }
    static var wifiOnly: Bool { UserDefaults.standard.bool(forKey: wifiOnlyKey) }
    static var deleteRead: Bool { UserDefaults.standard.bool(forKey: deleteReadKey) }
    static var lastCheck: Date? { UserDefaults.standard.object(forKey: lastCheckKey) as? Date }
}

enum DownloadStorage {
    /// Downloads live outside the CBZ library and are excluded from device backups (they can be re-fetched).
    static var directory: URL {
        var dir = URL.documentsDirectory.appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        return dir
    }

    static func totalBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
