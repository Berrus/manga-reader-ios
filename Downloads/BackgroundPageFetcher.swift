import CryptoKit
import Foundation
import UIKit

/// Downloads chapter pages through a background URL session so iOS keeps fetching them after the app
/// is suspended. Pages land in a cache folder keyed by URL; the normal download queue then finds them
/// there (this run or after a relaunch) instead of fetching again, so no queue logic changes.
///
/// shortcut: a page's size is checked after it has been downloaded (a background session can't cap
/// the bytes while streaming); pages come only from hosts the source's access policy allows.
final class BackgroundPageFetcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = BackgroundPageFetcher()
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "folioreader") + ".pages" }

    private let lock = NSLock()
    private var waiting: [Int: CheckedContinuation<Void, Error>] = [:]
    private var policies: [Int: SourceAccessPolicy] = [:]
    /// Set by the app delegate when iOS wakes the app for finished transfers.
    var backgroundCompletion: (() -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Recreates the session so iOS can deliver events that finished while the app was not running.
    func reconnect() { _ = session }

    // MARK: Cache

    static var cacheDirectory: URL { URL.cachesDirectory.appendingPathComponent("BackgroundPages", isDirectory: true) }

    static func cacheURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return cacheDirectory.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
    }

    /// Returns a cached page and removes it, or nil.
    private static func takeCached(_ file: URL) -> Data? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        try? FileManager.default.removeItem(at: file)
        return data
    }

    /// Files older than `maxAge` belong to chapters that were cancelled or never resumed (pure, unit tested).
    static func staleFiles(_ files: [(url: URL, modified: Date)], now: Date, maxAge: TimeInterval) -> [URL] {
        files.filter { now.timeIntervalSince($0.modified) > maxAge }.map(\.url)
    }

    static func purgeStaleCache(maxAge: TimeInterval = 24 * 3600) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: keys) else { return }
        let files = urls.map { ($0, (try? $0.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast) }
        staleFiles(files, now: Date(), maxAge: maxAge).forEach { try? FileManager.default.removeItem(at: $0) }
    }

    // MARK: Fetching

    /// Starts every page at once so they keep downloading while the app is in the background.
    func prefetch(_ pages: [PageSource], policy: SourceAccessPolicy) async {
        for page in pages {
            guard let url = URL(string: page.url), policy.allows(url),
                  !FileManager.default.fileExists(atPath: Self.cacheURL(for: url).path) else { continue }
            _ = await task(for: page, url: url, policy: policy)
        }
    }

    func fetch(_ page: PageSource, policy: SourceAccessPolicy) async throws -> Data {
        guard let url = URL(string: page.url), policy.allows(url) else { throw TransportError.blocked }
        let file = Self.cacheURL(for: url)
        if let data = Self.takeCached(file) { return data }
        let task = await task(for: page, url: url, policy: policy)
        try await wait(for: task)
        guard let data = Self.takeCached(file) else { throw DownloadError.badResponse(0) }
        return data
    }

    private func task(for page: PageSource, url: URL, policy: SourceAccessPolicy) async -> URLSessionDownloadTask {
        let existing = await session.allTasks
            .first { $0.taskDescription == url.absoluteString && $0.state != .completed } as? URLSessionDownloadTask
        if let existing {
            lock.lock(); policies[existing.taskIdentifier] = policy; lock.unlock()
            return existing
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        for (key, value) in page.headers ?? [:] { request.setValue(value, forHTTPHeaderField: key) }
        request.allowsCellularAccess = !DownloadSettings.wifiOnly
        let task = session.downloadTask(with: request)
        task.taskDescription = url.absoluteString
        lock.lock(); policies[task.taskIdentifier] = policy; lock.unlock()
        task.resume()
        return task
    }

    private func wait(for task: URLSessionDownloadTask) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if task.state == .completed { lock.unlock(); continuation.resume(); return }   // finished before we waited
                waiting[task.taskIdentifier] = continuation
                lock.unlock()
            }
        } onCancel: { task.cancel() }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let http = downloadTask.response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let original = downloadTask.originalRequest?.url,
              let size = (try? location.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= CBZArchive.maxPageBytes else { return }   // nothing cached: the waiting fetch reports the failure
        let destination = Self.cacheURL(for: original)
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: location, to: destination)   // must happen before this method returns
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = waiting.removeValue(forKey: task.taskIdentifier)
        policies.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); let policy = policies[task.taskIdentifier]; lock.unlock()
        // After a relaunch the policy isn't known, so redirects are refused rather than trusted.
        if let policy, let url = request.url, policy.allows(url) { completionHandler(request) } else { completionHandler(nil) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundPageFetcher.identifier else { completionHandler(); return }
        BackgroundPageFetcher.shared.backgroundCompletion = completionHandler
        BackgroundPageFetcher.shared.reconnect()
    }
}
