import SwiftUI

struct RemoteImage: View {
    let url: URL?
    var headers: [String: String] = [:]
    let policy: SourceAccessPolicy
    @State private var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    private var requestID: String {
        (url?.absoluteString ?? "") + headers.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined()
    }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Color.gray.opacity(0.3) }
        }.task(id: requestID) { await load() }
    }
    private func load() async {
        image = nil
        guard let url, policy.allows(url) else { return }
        Self.cache.totalCostLimit = 16 * 1024 * 1024
        let key = requestID as NSString
        if let cached = Self.cache.object(forKey: key) { image = cached; return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        guard let (data, _) = try? await SourceTransport.load(request, policy: policy, maxBytes: 10_000_000) else { return }
        let decoded = await Task.detached(priority: .utility) {
            ImageDownsampler.image(from: data, maxPixel: 400)
        }.value
        guard !Task.isCancelled, let decoded else { return }
        let cost = decoded.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        Self.cache.setObject(decoded, forKey: key, cost: cost)
        image = decoded
    }
}
