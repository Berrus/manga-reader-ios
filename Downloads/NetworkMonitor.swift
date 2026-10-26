import Foundation
import Network
import Observation

@MainActor @Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    // Unknown network state is not permission to use cellular.
    private(set) var isExpensive = true
    private(set) var isOnline = false
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive || path.isConstrained
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                self.isExpensive = expensive
                self.isOnline = online
                if self.canDownload { DownloadManager.shared.resume() }
                else { DownloadManager.shared.pause() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "network.monitor"))
    }
    var canDownload: Bool { isOnline && !(DownloadSettings.wifiOnly && isExpensive) }
}
