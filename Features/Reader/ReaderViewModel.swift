import SwiftUI

enum ImageFit { case screen, width }

@MainActor @Observable

final class ReaderViewModel {

    let chapter: Chapter

    private var archive: CBZArchive?

    private let cache = NSCache<NSNumber, UIImage>()

    private var inFlight: [Int: Task<UIImage?, Never>] = [:]

    var loadError: String?

    /// Set by the reader view from its actual size and display scale.
    @ObservationIgnored var viewport = CGSize(width: 820, height: 1180)
    @ObservationIgnored var displayScale: CGFloat = 2

    /// Webtoon pages stop growing past this width so iPad/Mac don't blow strips up edge to edge.
    nonisolated static let webtoonMaxWidth: CGFloat = 900

    var pageCount: Int { chapter.pageCount }

    init(chapter: Chapter) {
        self.chapter = chapter
        cache.countLimit = 10
    }

    /// Opens the archive on first use so constructing the view model stays cheap.
    func open() {
        guard archive == nil, loadError == nil else { return }
        do { archive = try CBZArchive(url: chapter.fileURL) }
        catch { loadError = "Couldn't open this file." }
    }

    func image(at index: Int, fit: ImageFit) async -> UIImage? {

        if let cached = cache.object(forKey: NSNumber(value: index)) { return cached }

        if let task = inFlight[index] { return await task.value }

        open()
        guard let archive else { return nil }

        // Size from the reader's real viewport (not the device screen) so iPad
        // multitasking and resizable Mac windows get right-sized bitmaps. The longest
        // side is used so rotating doesn't invalidate cached images.
        let longest = max(viewport.width, viewport.height)
        let screenPixels = min(longest * displayScale * 1.5, 4096)
        let widthPixels = min(longest, Self.webtoonMaxWidth) * displayScale

        let task = Task<UIImage?, Never> {

            guard let data = try? await archive.pageData(at: index) else { return nil }

            return await Task.detached(priority: .userInitiated) {

                switch fit {

                case .screen: return ImageDownsampler.image(from: data, maxPixel: screenPixels)

                case .width:  return ImageDownsampler.image(from: data, fittingWidth: widthPixels)

                }

            }.value

        }

        inFlight[index] = task

        let image = await task.value

        inFlight[index] = nil

        if let image { cache.setObject(image, forKey: NSNumber(value: index)) }

        return image

    }

    func preload(around index: Int, fit: ImageFit) {

        for i in [index + 1, index + 2, index + 3, index - 1] where i >= 0 && i < pageCount {

            Task { _ = await image(at: i, fit: fit) }

        }

    }

    func clearCache() { cache.removeAllObjects() }

    /// `markRead` is false on appear so merely opening the last page doesn't finish the chapter.
    func saveProgress(_ page: Int, markRead: Bool = true) {
        chapter.lastPage = page
        if markRead && page >= pageCount - 1 { chapter.isRead = true }
    }

}

