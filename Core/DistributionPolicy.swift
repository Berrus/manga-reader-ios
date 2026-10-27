import Foundation

/// Compile-time distribution boundary, never controlled by a server or hidden switch.
enum DistributionPolicy {
    #if APP_STORE
    static let allowsPublicSources = false
    static let allowsCustomSources = true
    #else
    static let allowsPublicSources = true
    static let allowsCustomSources = true
    #endif

    /// Suwayomi servers run third-party extensions, so they follow the custom-source decision.
    static var allowsSuwayomi: Bool { allowsCustomSources }
}
