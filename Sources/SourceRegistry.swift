import Foundation

/// Finds the live `Source` for a source id saved on a library series.
@MainActor
enum SourceRegistry {
    static func source(id: String) -> (any Source)? {
        if DistributionPolicy.allowsPublicSources && id == "mangadex" { return MangaDexSource() }
        if id.hasPrefix("komga."), let uuid = UUID(uuidString: String(id.dropFirst("komga.".count))),
           let server = ServerStore.shared.servers.first(where: { $0.id == uuid }) {
            return ServerStore.shared.source(for: server)
        }
        if DistributionPolicy.allowsCustomSources, let manifest = SourceStore.shared.manifests.first(where: { $0.id == id }) {
            return SourceStore.shared.source(for: manifest)
        }
        return nil
    }
}
