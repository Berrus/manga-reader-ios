import SwiftUI

enum ImageFit: String { case screen, width }

@MainActor @Observable
final class ReaderViewModel {
    let chapter: Chapter
    private var archive: (any PageProvider)?
    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var inFlight: [String: Task<UIImage?, Never>] = [:]
    @ObservationIgnored private var generation = 0
    var loadError: String?

    /// Set by the reader view from its actual size and display scale.
    @ObservationIgnored private(set) var viewport = CGSize(width: 820, height: 1180)
    @ObservationIgnored private(set) var displayScale: CGFloat = 2

    /// Webtoon pages stop growing past this width so iPad/Mac don't blow strips up edge to edge.
    nonisolated static let webtoonMaxWidth: CGFloat = 900

    var imageRevision = 0
    var failedPages: Set<Int> = []
    private(set) var preloadCount = 2
    private(set) var cacheLimitMB = 64
    var pageCount: Int { chapter.pageCount }

    init(chapter: Chapter) {
        self.chapter = chapter
        cache.countLimit = 10
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func open() {
        guard archive == nil, loadError == nil else { return }
        do {
            if chapter.isRemote {
                guard chapter.isDownloaded else { throw CBZError.unreadable }
                archive = try DirectoryPages(directory: chapter.downloadDirectory)
            } else {
                archive = try CBZArchive(url: chapter.fileURL)
            }
        }
        catch { loadError = "Couldn't open this file." }
    }

    func image(at index: Int, fit: ImageFit) async -> UIImage? {
        guard (0..<pageCount).contains(index) else { return nil }
        let key = "\(fit.rawValue):\(index)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] {
            let revision = generation
            let result = await task.value
            return revision == generation && !task.isCancelled ? result : nil
        }
        open()
        guard let archive else { return nil }
        let requestGeneration = generation

        // Size from the reader's real viewport (not the device screen) so iPad
        // multitasking and resizable Mac windows get right-sized bitmaps. The longest
        // side is used so rotating doesn't invalidate cached images.
        let longest = max(viewport.width, viewport.height)
        let screenPixels = min(longest * displayScale * 1.5, 4096)
        let widthPixels = min(longest, Self.webtoonMaxWidth) * displayScale

        let task = Task<UIImage?, Never> {
            guard !Task.isCancelled,
                  let data = try? await archive.pageData(at: index),
                  !Task.isCancelled else { return nil }
            return await Task.detached(priority: .userInitiated) {
                switch fit {
                case .screen: return ImageDownsampler.image(from: data, maxPixel: screenPixels)
                case .width: return ImageDownsampler.image(from: data, fittingWidth: widthPixels)
                }
            }.value
        }
        inFlight[key] = task
        let image = await task.value
        // Old decodes must not repopulate a cleared cache or erase newer requests.
        guard requestGeneration == generation, !task.isCancelled else { return nil }
        inFlight[key] = nil
        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(image, forKey: key as NSString, cost: cost)
            failedPages.remove(index)
        } else {
            failedPages.insert(index)
        }
        return image
    }

    func preload(around index: Int, fit: ImageFit) {
        guard preloadCount > 0 else { return }
        let candidates = (1...preloadCount).map { index + $0 } + [index - 1]
        for i in candidates where i >= 0 && i < pageCount {
            Task { _ = await image(at: i, fit: fit) }
        }
    }

    func configureMemory(preload: Int, cacheMB: Int) {
        let preload = ReaderTuning.preload(preload)
        let cacheMB = ReaderTuning.cacheMB(cacheMB)
        guard preload != preloadCount || cacheMB != cacheLimitMB else { return }
        preloadCount = preload
        cacheLimitMB = cacheMB
        cache.countLimit = max(4, preload * 2 + 2)
        cache.totalCostLimit = cacheMB * 1024 * 1024
        clearCache()
    }

    func configureViewport(_ size: CGSize, scale: CGFloat) {
        guard size.width > 0, size.height > 0, scale > 0, scale.isFinite,
              size != viewport || scale != displayScale else { return }
        viewport = size
        displayScale = scale
        clearCache()
    }

    func clearCache() {
        generation += 1
        imageRevision += 1
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        cache.removeAllObjects()
        failedPages.removeAll()
    }

    func saveProgress(_ page: Int, markRead: Bool = true) {
        guard pageCount > 0 else { return }
        if let manga = chapter.manga {
            manga.lastReadAt = .now
            manga.lastReadChapterName = chapter.name
        }
        chapter.lastPage = min(max(page, 0), pageCount - 1)
        if markRead && (0..<pageCount).contains(page) && page == pageCount - 1 {
            let wasRead = chapter.isRead
            chapter.isRead = true
            if !wasRead, let manga = chapter.manga {
                Task { await TrackerSync.shared.syncAfterReading(manga) }
            }
        }
    }
}
