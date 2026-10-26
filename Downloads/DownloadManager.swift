import Foundation
import Observation
import SwiftData
import UIKit

enum DownloadError: LocalizedError {
    case sourceUnavailable, badResponse(Int), noPages

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: return "The source isn't available. Check your servers and sources in Settings."
        case .badResponse(let code): return "The server answered with error \(code)."
        case .noPages: return "The chapter has no pages."
        }
    }
}

/// Downloads remote chapters to disk one at a time. Runs while the app is active (plus the short
/// extra time iOS grants when it goes to the background); the queue resumes next time the app runs.
@MainActor @Observable
final class DownloadManager {
    static let shared = DownloadManager()

    struct Job: Identifiable, Equatable {
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

    func progress(for chapter: Chapter) -> Double? {
        jobs.first { $0.chapterID == chapter.id }?.progress
    }

    func state(for chapter: Chapter) -> Job? { jobs.first { $0.chapterID == chapter.id } }

    func enqueue(_ list: [Chapter]) {
        for chapter in list where chapter.isRemote && !chapter.isDownloaded
            && !jobs.contains(where: { $0.chapterID == chapter.id }) {
            chapters[chapter.id] = chapter
            jobs.append(Job(chapterID: chapter.id, title: "\(chapter.manga?.title ?? "") – \(chapter.name)"))
        }
        pump()
    }

    func cancel(chapterID: UUID) {
        jobs.removeAll { $0.chapterID == chapterID && !$0.isActive }
        if jobs.first(where: { $0.chapterID == chapterID })?.isActive == true { currentTask?.cancel() }
        chapters[chapterID] = nil
    }

    func cancelAll() {
        currentTask?.cancel()
        jobs.removeAll()
        chapters.removeAll()
    }

    func retryFailed() {
        for index in jobs.indices where jobs[index].failure != nil { jobs[index].failure = nil }
        pump()
    }

    // MARK: Queue

    private func pump() {
        guard !isPumping else { return }
        isPumping = true
        var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask(withName: "downloads") { [weak self] in
            self?.currentTask?.cancel()
            UIApplication.shared.endBackgroundTask(background)
        }
        currentTask = Task { [weak self] in
            await self?.run()
            self?.isPumping = false
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
    }

    private func run() async {
        while let index = jobs.firstIndex(where: { $0.failure == nil }) {
            guard NetworkMonitor.shared.canDownload else { break }
            let job = jobs[index]
            guard let chapter = chapters[job.chapterID] else { jobs.remove(at: index); continue }
            jobs[index].isActive = true
            do {
                try await download(chapter)
                remove(job.chapterID)
            } catch is CancellationError {
                remove(job.chapterID)
                if Task.isCancelled { break }
            } catch {
                if let i = jobs.firstIndex(where: { $0.chapterID == job.chapterID }) {
                    jobs[i].isActive = false
                    jobs[i].failure = error.localizedDescription
                }
            }
        }
    }

    private func remove(_ id: UUID) {
        jobs.removeAll { $0.chapterID == id }
        chapters[id] = nil
    }

    private func setProgress(_ id: UUID, _ value: Double) {
        if let i = jobs.firstIndex(where: { $0.chapterID == id }) { jobs[i].progress = value }
    }

    // MARK: One chapter

    private func download(_ chapter: Chapter) async throws {
        guard let manga = chapter.manga, let sourceID = manga.sourceID, let remoteID = chapter.remoteID,
              let source = SourceRegistry.source(id: sourceID) else { throw DownloadError.sourceUnavailable }

        let pages = try await source.pages(for: ChapterSummary(id: remoteID, name: chapter.name, number: chapter.number))
        guard !pages.isEmpty else { throw DownloadError.noPages }

        let final = chapter.downloadDirectory
        let partial = final.deletingLastPathComponent().appendingPathComponent("\(chapter.id.uuidString).part", isDirectory: true)
        try? FileManager.default.removeItem(at: partial)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)

        do {
            for (index, page) in pages.enumerated() {
                try Task.checkCancellation()
                let data = try await Self.fetch(page)
                let ext = URL(string: page.url)?.pathExtension.lowercased()
                let name = String(format: "%04d.%@", index + 1, (ext?.isEmpty == false ? ext! : "img"))
                try data.write(to: partial.appendingPathComponent(name), options: .atomic)
                setProgress(chapter.id, Double(index + 1) / Double(pages.count))
            }
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: partial, to: final)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }

        chapter.pageCount = pages.count
        chapter.isDownloaded = true
        try? chapter.modelContext?.save()
    }

    /// Fetches one page, retrying twice on failure.
    private static func fetch(_ page: PageSource) async throws -> Data {
        guard let url = URL(string: page.url), let scheme = url.scheme, ["https", "http"].contains(scheme) else {
            throw DownloadError.badResponse(0)
        }
        var lastError: Error = DownloadError.badResponse(0)
        for attempt in 0..<3 {
            do {
                try Task.checkCancellation()
                var request = URLRequest(url: url, timeoutInterval: 30)
                for (key, value) in page.headers ?? [:] { request.setValue(value, forHTTPHeaderField: key) }
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw DownloadError.badResponse(http.statusCode)
                }
                guard data.count < 30_000_000 else { throw DownloadError.badResponse(413) }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 700_000_000)
            }
        }
        throw lastError
    }
}
