import Foundation

/// Compile-time distribution boundary, never controlled by a server or hidden switch.
enum DistributionPolicy {
    #if APP_STORE
    static let allowsPublicSources = false
    static let allowsCustomSources = true
    /// No script engine is compiled into this configuration (see Sources/ScriptedSource.swift).
    static let allowsScriptedSources = false
    #else
    static let allowsPublicSources = true
    static let allowsCustomSources = true
    static let allowsScriptedSources = true
    #endif

    /// Suwayomi servers run third-party extensions, so they follow the custom-source decision.
    static var allowsSuwayomi: Bool { allowsCustomSources }
    /// Installing extension repositories and extensions on a server is left out of the App Store build.
    static var allowsExtensionManagement: Bool { allowsSuwayomi && allowsPublicSources }
}
