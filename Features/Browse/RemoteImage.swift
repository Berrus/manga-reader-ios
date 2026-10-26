import SwiftUI

/// Loads a cover image, optionally with authentication headers (AsyncImage can't send them).
struct RemoteImage: View {
    let url: URL?
    var headers: [String: String] = [:]
    @State private var image: UIImage?

    private static let cache = NSCache<NSURL, UIImage>()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { image = nil; return }
        if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
        let decoded = await Task.detached(priority: .utility) {
            ImageDownsampler.image(from: data, maxPixel: 400)
        }.value
        if let decoded {
            Self.cache.setObject(decoded, forKey: url as NSURL)
            image = decoded
        }
    }
}
