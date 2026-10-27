import Foundation
import Observation
import SwiftData

/// Opt-in sync of library metadata (categories, reading progress, tracker links) through iCloud Drive.
///
/// Each device writes only its own file, `backup-<device id>.json`, and merges the other devices' files
/// with the same forward-only restore used for backups. Because no two devices write the same file there
/// are no write conflicts, and progress can only move forward. Comic files, credentials and deletions
/// do not sync. Needs the iCloud Documents entitlement (see docs/ICLOUD_SYNC.md); without it
/// `isAvailable` is false and nothing happens.
@MainActor @Observable
final class ICloudSync {
    static let shared = ICloudSync()

    private static let enabledKey = "sync.icloud.enabled"
    private static let deviceKey = "sync.icloud.device"
    private static let mergedKey = "sync.icloud.merged"
    private static let lastKey = "sync.icloud.last"
    static let minimumInterval: TimeInterval = 15 * 60

    private(set) var enabled = UserDefaults.standard.bool(forKey: ICloudSync.enabledKey)
    private(set) var isSyncing = false
    private(set) var message: String?

    var lastSync: Date? { UserDefaults.standard.object(forKey: Self.lastKey) as? Date }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
    }

    /// False when the build has no iCloud entitlement or the user is signed out of iCloud.
    func checkAvailability() async -> Bool {
        await Task.detached { FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil }.value
    }

    func syncIfNeeded(context: ModelContext) async {
        if let last = lastSync, Date().timeIntervalSince(last) < Self.minimumInterval { return }
        await syncNow(context: context)
    }

    func syncNow(context: ModelContext) async {
        guard enabled, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        guard let container = await Task.detached(operation: { FileManager.default.url(forUbiquityContainerIdentifier: nil) }).value else {
            message = "iCloud isn't available. Sign in to iCloud, or see docs/ICLOUD_SYNC.md for enabling it in a build."
            return
        }
        let folder = container.appendingPathComponent("Documents/FolioReader", isDirectory: true)
        let ownName = Self.fileName(device: deviceID)
        do {
            // 1. Publish this device's metadata.
            let data = try BackupService.encode(BackupService.snapshot(context: context))
            try await Task.detached {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appendingPathComponent(ownName), options: .atomic)
            }.value

            // 2. Merge what the other devices published.
            let files = try await Task.detached { try Self.listFiles(in: folder) }.value
            var merged = mergedDates
            var summary = RestoreSummary()
            var waiting = 0
            for name in Self.filesToMerge(files.map { ($0.name, $0.modified) }, ownName: ownName, merged: merged) {
                guard let file = files.first(where: { $0.name == name }) else { continue }
                guard file.isDownloaded else {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: file.url)   // picked up next sync
                    waiting += 1
                    continue
                }
                let bytes = try await Task.detached { try Self.coordinatedRead(file.url) }.value
                let result = try BackupService.restore(try BackupService.decode(bytes), into: context)
                summary.series += result.series; summary.chapters += result.chapters
                summary.categories += result.categories; summary.links += result.links
                merged[name] = file.modified
            }
            mergedDates = merged
            UserDefaults.standard.set(Date(), forKey: Self.lastKey)
            message = "Synced. \(summary.chapters) chapter\(summary.chapters == 1 ? "" : "s") updated from other devices."
                + (waiting > 0 ? " \(waiting) file\(waiting == 1 ? " is" : "s are") still downloading from iCloud." : "")
        } catch {
            message = "Sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: Helpers

    private var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: Self.deviceKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: Self.deviceKey)
        return id
    }

    private var mergedDates: [String: Date] {
        get { (UserDefaults.standard.dictionary(forKey: Self.mergedKey) as? [String: Date]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.mergedKey) }
    }

    nonisolated static func fileName(device: String) -> String { "backup-\(device).json" }

    /// Other devices' files that are new or changed since they were last merged (pure, unit tested).
    nonisolated static func filesToMerge(_ files: [(name: String, modified: Date)], ownName: String,
                                         merged: [String: Date]) -> [String] {
        files.filter {
            $0.name.hasPrefix("backup-") && $0.name.hasSuffix(".json") && $0.name != ownName
                && $0.modified > (merged[$0.name] ?? .distantPast)
        }.map(\.name).sorted()
    }

    private struct SyncFile: Sendable {
        let name: String
        let url: URL
        let modified: Date
        let isDownloaded: Bool
    }

    private nonisolated static func listFiles(in folder: URL) throws -> [SyncFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .ubiquitousItemDownloadingStatusKey]
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys).map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            // Files outside iCloud report no status and are always readable.
            let downloaded = values?.ubiquitousItemDownloadingStatus.map { $0 == .current } ?? true
            return SyncFile(name: url.lastPathComponent, url: url,
                            modified: values?.contentModificationDate ?? .distantPast, isDownloaded: downloaded)
        }
    }

    private nonisolated static func coordinatedRead(_ url: URL) throws -> Data {
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            result = Result { try Data(contentsOf: readable) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}
