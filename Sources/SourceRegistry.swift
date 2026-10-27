import Foundation

/// Finds the live `Source` for a source id saved on a library series.
@MainActor
enum SourceRegistry {
    static var available: [any Source] {
        var result: [any Source] = []
        if DistributionPolicy.allowsPublicSources { result.append(MangaDexSource()) }
        for server in ServerStore.shared.servers {
            if let source = ServerStore.shared.source(for: server) { result.append(source) }
        }
        if DistributionPolicy.allowsCustomSources && SourceStore.shared.enabled {
            for manifest in SourceStore.shared.manifests {
                if let source = SourceStore.shared.source(for: manifest) { result.append(source) }
            }
        }
        #if !APP_STORE
        if DistributionPolicy.allowsScriptedSources && ScriptedSourceStore.shared.enabled {
            for manifest in ScriptedSourceStore.shared.manifests {
                if let source = ScriptedSourceStore.shared.source(for: manifest) { result.append(source) }
            }
        }
        if DistributionPolicy.allowsScriptedSources && PaperbackStore.shared.enabled {
            for info in PaperbackStore.shared.installed {
                if let source = PaperbackStore.shared.source(for: info) { result.append(source) }
            }
        }
        #endif
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }
    static func source(id: String) -> (any Source)? {
        if DistributionPolicy.allowsPublicSources && id == "mangadex" { return MangaDexSource() }
        if id.hasPrefix("komga."), let uuid = UUID(uuidString: String(id.dropFirst("komga.".count))),
           let server = ServerStore.shared.servers.first(where: { $0.id == uuid }) {
            return ServerStore.shared.source(for: server)
        }
        if id.hasPrefix("opds."), let uuid = UUID(uuidString: String(id.dropFirst("opds.".count))),
           let server = ServerStore.shared.servers.first(where: { $0.id == uuid }) {
            return ServerStore.shared.source(for: server)
        }
        if let parsed = SuwayomiSource.parseID(id) {
            return ServerStore.shared.suwayomiSource(serverID: parsed.server, sourceID: parsed.source)
        }
        #if !APP_STORE
        if DistributionPolicy.allowsScriptedSources, id.hasPrefix("js."), let source = ScriptedSourceStore.shared.source(id: id) { return source }
        if DistributionPolicy.allowsScriptedSources, id.hasPrefix("pb."), let source = PaperbackStore.shared.source(id: id) { return source }
        #endif
        if DistributionPolicy.allowsCustomSources, let manifest = SourceStore.shared.manifests.first(where: { $0.id == id }) {
            return SourceStore.shared.source(for: manifest)
        }
        return nil
    }
}
