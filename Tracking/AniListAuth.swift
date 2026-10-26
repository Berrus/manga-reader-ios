import AuthenticationServices
import Observation
import UIKit

enum AniListAuthError: LocalizedError {
    case missingClientID, cancelled, noToken

    var errorDescription: String? {
        switch self {
        case .missingClientID: return "No AniList client ID is set. See the README."
        case .cancelled: return "Sign-in was cancelled."
        case .noToken: return "AniList didn't return a token."
        }
    }
}

/// AniList sign-in using the implicit grant (no client secret is stored in the app).
/// The access token lives in the Keychain.
@MainActor @Observable
final class AniListAuth {
    static let shared = AniListAuth()

    static let callbackScheme = "folioreader"
    private static let account = "anilist.token"

    private(set) var isConnected = Keychain.get(AniListAuth.account) != nil

    @ObservationIgnored private var session: ASWebAuthenticationSession?
    @ObservationIgnored private let anchor = PresentationAnchor()

    /// Set via the ANILIST_CLIENT_ID build setting in project.yml.
    var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "AniListClientID") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    var hasClientID: Bool { !clientID.isEmpty && !clientID.hasPrefix("$(") }

    /// Registers the tracker if we already have a token (call at launch).
    func restore() {
        isConnected = Keychain.get(Self.account) != nil
        if isConnected { registerTracker() }
    }

    func connect() async throws {
        guard hasClientID else { throw AniListAuthError.missingClientID }
        var components = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "token")
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!,
                                                     callbackURLScheme: Self.callbackScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? AniListAuthError.cancelled) }
            }
            session.presentationContextProvider = anchor
            self.session = session
            session.start()
        }
        guard let token = Self.token(from: callback) else { throw AniListAuthError.noToken }
        Keychain.set(token, for: Self.account)
        isConnected = true
        registerTracker()
    }

    func disconnect() {
        Keychain.remove(Self.account)
        isConnected = false
        TrackerSync.shared.unregister(id: "anilist")
    }

    private func registerTracker() {
        TrackerSync.shared.register(AniListTracker(tokenProvider: { Keychain.get(AniListAuth.account) }))
    }

    /// The token arrives in the URL fragment: folioreader://anilist#access_token=...&token_type=Bearer
    nonisolated static func token(from url: URL) -> String? {
        guard let fragment = url.fragment,
              let items = URLComponents(string: "?" + fragment)?.queryItems else { return nil }
        return items.first { $0.name == "access_token" }?.value
    }
}

private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
