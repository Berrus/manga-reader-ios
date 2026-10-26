import Foundation
import Network
import Observation

/// Tracks whether the current connection is metered (cellular or personal hotspot).
@MainActor @Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isExpensive = false
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.isExpensive
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isExpensive = expensive
                self?.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "network.monitor"))
    }

    /// True when a download is allowed to start under the user's Wi-Fi-only setting.
    var canDownload: Bool { isOnline && !(DownloadSettings.wifiOnly && isExpensive) }
}
