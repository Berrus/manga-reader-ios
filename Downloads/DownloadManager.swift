import Foundation
import Observation
import SwiftData
import UIKit
import ImageIO

enum DownloadError: LocalizedError {
    case sourceUnavailable, badResponse(Int), noPages, invalidImage
    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: return "The source isn't available. Check Settings."
        case .badResponse(let code): return "The server answered with error \(code)."
        case .noPages: return "The chapter has no pages."
        case .invalidImage: return "A downloaded page is not a readable image."
        }
    }
}

@MainActor @Observable
final class DownloadManager {
    static let shared = DownloadManager()

    struct Job: Identifiable, Equatable, Codable {
        let chapterID: UUID
        var title: String
        var progress: Double = 0
        var isActive = false
        var failure: String?
        var id: UUID { chapterID }
    }
    private(set) var jobs: [Job] = []
    private(set) var isPumping = false
    @ObservationIgnored private var chapters: [UUID: Chapter] = [:]
    @ObservationIgnored private var currentTask: Task<Void, Never>?
    @ObservationIgnored private var activeDownload: Task<Void, Error>?
    @ObservationIgnored private var activeID: UUID?
    @ObservationIgnored private var cancelledIDs: Set<UUID> = []
    @ObservationIgnored private var paused = false
    @ObservationIgnored private let queueURL: URL
    @ObservationIgnored private let canDownload: @MainActor () -> Bool
    @ObservationIgnored private let resolve: @MainActor (String) -> (any Source)?
    @ObservationIgnored private let fetchPage: (PageSource, SourceAccessPolicy) async throws -> Data

    init(queueURL: URL = URL.applicationSupportDirectory.appendingPathComponent("download-queue.json"),
         canDownload: @escaping @MainActor () -> Bool = { NetworkMonitor.shared.canDownload },
         resolve: @escaping @MainActor (String) -> (any Source)? = { SourceRegistry.source(id: $0) },
         fetchPage: @escaping (PageSource, SourceAccessPolicy) async throws -> Data = DownloadManager.fetch) {
        self.queueURL = queueURL
        self.canDownload = canDownload
        self.resolve = resolve
        self.fetchPage = fetchPage
        if let handle = try? FileHandle(forReadingFrom: queueURL) {
            defer { try? handle.close() }
            if let data = try? handle.read(upToCount: 4_000_001), data.count <= 4_000_000,
               let saved = try? JSONDecoder().decode([Job].self, from: data) {
                var seen = Set<UUID>()
                jobs = saved.filter { seen.insert($0.chapterID).inserted }.map {
                    var job = $0; job.isActive = false; job.progress = 0; return job
                }
            }
        }
    }

    func progress(for chapter: Chapter) -> Double? { state(for: chapter)?.progress }
    func state(for chapter: Chapter) -> Job? { jobs.first { $0.chapterID == chapter.id } }

    func enqueue(_ list: [Chapter]) {
        for chapter in list where chapter.isRemote && !chapter.isDownloaded &&
            !jobs.contains(where: { $0.chapterID == chapter.id }) {
            guard let context = chapter.modelContext else { continue }
            do { try context.save() }
            catch { continue }
            cancelledIDs.remove(chapter.id)
            chapters[chapter.id] = chapter
            jobs.append(Job(chapterID: chapter.id, title: "\(chapter.manga?.title ?? "") – \(chapter.name)"))
        }
        persist()
        paused = false
        pump()
    }

    func cancel(chapterID: UUID) {
        cancelledIDs.insert(chapterID)
        if activeID == chapterID { activeDownload?.cancel() }
        else { remove(chapterID) }
        persist()
    }
    func cancelAll() { for id in jobs.map(\.chapterID) { cancel(chapterID: id) } }

    /// Await acknowledgement before deleting models or files owned by these jobs.
    func cancelAndWait(_ ids: Set<UUID>) async {
        for id in ids { cancel(chapterID: id) }
        if let activeID, ids.contains(activeID), let task = activeDownload { _ = try? await task.value }
        for id in ids { remove(id) }
        persist()
    }

    func pause() {
        paused = true
        currentTask?.cancel()
        activeDownload?.cancel()
    }
    func resume(context: ModelContext? = nil) {
        if let context {
            let all = (try? context.fetch(FetchDescriptor<Chapter>())) ?? []
            let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            for job in jobs {
                if let chapter = byID[job.chapterID], chapter.isRemote, !chapter.isDownloaded {
                    chapters[job.chapterID] = chapter
                } else { remove(job.chapterID) }
            }
            persist()
        }
        paused = false
        pump()
    }
    func retryFailed() {
        for index in jobs.indices { jobs[index].failure = nil }
        persist()
        paused = false
        pump()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: queueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(jobs)
            guard data.count <= 4_000_000 else { throw TransportError.tooLarge }
            try data.write(to: queueURL, options: .atomic)
        } catch {
            // Show persistence failure; never pretend the queue is durable.
            for index in jobs.indices where jobs[index].failure == nil {
                jobs[index].failure = "Couldn't save the download queue: \(error.localizedDescription)"
            }
        }
    }
    private func remove(_ id: UUID) {
        jobs.removeAll { $0.chapterID == id }
        chapters[id] = nil
    }

    private func pump() {
        guard !isPumping, !paused, canDownload(),
              jobs.contains(where: { $0.failure == nil && chapters[$0.chapterID] != nil }) else { return }
        isPumping = true
        currentTask = Task { [weak self] in
            guard let self else { return }
            let background = UIApplication.shared.beginBackgroundTask(withName: "downloads") { [weak self] in
                Task { @MainActor in self?.pause() }
            }
            await run()
            activeID = nil
            activeDownload = nil
            isPumping = false
            currentTask = nil
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
            if !paused && canDownload() { pump() }
        }
    }
    private func run() async {
        while !Task.isCancelled, !paused, canDownload(),
              let index = jobs.firstIndex(where: { $0.failure == nil && chapters[$0.chapterID] != nil }) {
            let job = jobs[index]
            guard let chapter = chapters[job.chapterID] else { break }
            jobs[index].isActive = true
            activeID = job.chapterID
            let task = Task { try await self.download(chapter) }
            activeDownload = task
            do {
                try await task.value
                remove(job.chapterID)
            } catch is CancellationError {
                if cancelledIDs.remove(job.chapterID) != nil { remove(job.chapterID) }
                else if chapter.modelContext == nil { remove(job.chapterID) }
                else if let i = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[i].isActive = false; jobs[i].progress = 0
                }
            } catch {
                if let i = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[i].isActive = false
                    jobs[i].failure = error.localizedDescription
                }
            }
            activeID = nil
            activeDownload = nil
            persist()
        }
    }

    private func download(_ chapter: Chapter) async throws {
        let chapterID = chapter.id
        guard let manga = chapter.manga, let sourceID = manga.sourceID, let remoteID = chapter.remoteID,
              let source = resolve(sourceID) else { throw DownloadError.sourceUnavailable }
        try Task.checkCancellation()
        let pages = try await source.pages(for: ChapterSummary(id: remoteID, name: chapter.name, number: chapter.number))
        guard !pages.isEmpty, pages.count <= 10_000 else { throw DownloadError.noPages }
        if DownloadSettings.backgroundTransfers { await BackgroundPageFetcher.shared.prefetch(pages, policy: source.accessPolicy) }
        let final = chapter.downloadDirectory
        let partial = final.deletingLastPathComponent().appendingPathComponent("\(chapterID.uuidString).part", isDirectory: true)
        try? FileManager.default.removeItem(at: partial)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: partial) }

        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            guard !cancelledIDs.contains(chapterID), !paused, canDownload() else { throw CancellationError() }
            let data = try await fetchPage(page, source.accessPolicy)
            try Task.checkCancellation()
            guard !cancelledIDs.contains(chapterID), !paused, canDownload() else { throw CancellationError() }
            guard data.count <= CBZArchive.maxPageBytes,
                  CGImageSourceCreateWithData(data as CFData, nil) != nil else { throw DownloadError.invalidImage }
            try data.write(to: partial.appendingPathComponent(String(format: "%05d.img", index + 1)), options: .atomic)
            if let i = jobs.firstIndex(where: { $0.id == chapterID }) {
                jobs[i].progress = Double(index + 1) / Double(pages.count)
            }
        }
        // The commit has no suspension point: cancellation/deletion cannot interleave here.
        try Task.checkCancellation()
        guard !cancelledIDs.contains(chapterID), !paused, canDownload(),
              chapter.modelContext != nil, chapter.manga != nil else { throw CancellationError() }
        let oldCount = chapter.pageCount
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: partial, to: final)
        chapter.pageCount = pages.count
        chapter.isDownloaded = true
        do { try chapter.modelContext?.save() }
        catch {
            chapter.pageCount = oldCount
            chapter.isDownloaded = false
            try? FileManager.default.removeItem(at: final)
            throw error
        }
    }

    nonisolated private static func fetch(_ page: PageSource, _ policy: SourceAccessPolicy) async throws -> Data {
        guard let url = URL(string: page.url), policy.allows(url) else { throw TransportError.blocked }
        if DownloadSettings.backgroundTransfers { return try await BackgroundPageFetcher.shared.fetch(page, policy: policy) }
        var lastError: Error = DownloadError.badResponse(0)
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: url, timeoutInterval: 30)
                for (key, value) in page.headers ?? [:] { request.setValue(value, forHTTPHeaderField: key) }
                return try await SourceTransport.load(request, policy: policy, maxBytes: CBZArchive.maxPageBytes).0
            } catch is CancellationError { throw CancellationError() }
            catch {
                lastError = error
                if attempt < 2 { try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 700_000_000) }
            }
        }
        throw lastError
    }
}
