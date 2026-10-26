import SwiftUI

enum ImageFit: String { case screen, width }

@MainActor @Observable
final class ReaderViewModel {
    let chapter: Chapter
    private var archive: CBZArchive?
    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var inFlight: [String: Task<UIImage?, Never>] = [:]
    @ObservationIgnored private var generation = 0
    var loadError: String?
    var failedPages: Set<Int> = []
    var pageCount: Int { chapter.pageCount }

    init(chapter: Chapter) {
        self.chapter = chapter
        cache.countLimit = 10
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func open() {
        guard archive == nil, loadError == nil else { return }
        do { archive = try CBZArchive(url: chapter.fileURL) }
        catch { loadError = "Couldn't open this file." }
    }

    func image(at index: Int, fit: ImageFit) async -> UIImage? {
        guard (0..<pageCount).contains(index) else { return nil }
        let key = "\(fit.rawValue):\(index)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }
        open()
        guard let archive else { return nil }
        let requestGeneration = generation
        let screenPixels = UIScreen.main.bounds.height * UIScreen.main.scale * 1.5
        let widthPixels = UIScreen.main.bounds.width * UIScreen.main.scale
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
        for i in [index + 1, index + 2, index - 1] where i >= 0 && i < pageCount {
            Task { _ = await image(at: i, fit: fit) }
        }
    }

    func clearCache() {
        generation += 1
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        cache.removeAllObjects()
        failedPages.removeAll()
    }

    func saveProgress(_ page: Int, markRead: Bool = true) {
        guard pageCount > 0 else { return }
        chapter.lastPage = min(max(page, 0), pageCount - 1)
        if markRead && (0..<pageCount).contains(page) && page == pageCount - 1 {
            chapter.isRead = true
        }
    }
}
