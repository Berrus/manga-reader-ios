import AuthenticationServices
import Foundation
import Observation
import Security

enum MyAnimeListAuthError: LocalizedError {
    case missingClientID, cancelled, badResponse, stateMismatch

    var errorDescription: String? {
        switch self {
        case .missingClientID: return "No MyAnimeList client ID is set. See the README."
        case .cancelled: return "Sign-in was cancelled."
        case .badResponse: return "MyAnimeList didn't return a usable sign-in."
        case .stateMismatch: return "The sign-in response didn't match the request. Try again."
        }
    }
}

/// MyAnimeList sign-in: authorization code with PKCE (no client secret is stored in the app).
/// MyAnimeList only supports the "plain" PKCE method. Access tokens last about an hour, so they
/// are refreshed with the refresh token; both live in the Keychain.
@MainActor @Observable
final class MyAnimeListAuth {
    static let shared = MyAnimeListAuth()

    static let callbackScheme = "folioreader"
    static let redirectURI = "folioreader://mal"
    private static let accessKey = "mal.access"
    private static let refreshKey = "mal.refresh"
    private static let expiryKey = "mal.expiry"
    private static let tokenURL = URL(string: "https://myanimelist.net/v1/oauth2/token")!

    private(set) var isConnected = Keychain.get(MyAnimeListAuth.refreshKey) != nil

    @ObservationIgnored private var session: ASWebAuthenticationSession?
    @ObservationIgnored private let anchor = PresentationAnchor()
    @ObservationIgnored private var refreshing: Task<String, Error>?

    /// Set via the MAL_CLIENT_ID build setting in project.yml.
    var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "MyAnimeListClientID") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    var hasClientID: Bool { !clientID.isEmpty && !clientID.hasPrefix("$(") }

    func restore() {
        isConnected = Keychain.get(Self.refreshKey) != nil
        if isConnected { registerTracker() }
    }

    func connect() async throws {
        guard hasClientID else { throw MyAnimeListAuthError.missingClientID }
        let verifier = Self.randomString()
        let state = Self.randomString()
        let url = Self.authorizeURL(clientID: clientID, verifier: verifier, state: state)

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? MyAnimeListAuthError.cancelled) }
            }
            session.presentationContextProvider = anchor
            self.session = session
            session.start()
        }
        guard let code = try Self.code(from: callback, expectedState: state) else { throw MyAnimeListAuthError.badResponse }
        _ = try await requestToken(["grant_type": "authorization_code", "code": code,
                                    "redirect_uri": Self.redirectURI, "code_verifier": verifier])
        isConnected = true
        registerTracker()
    }

    func disconnect() {
        [Self.accessKey, Self.refreshKey].forEach(Keychain.remove)
        UserDefaults.standard.removeObject(forKey: Self.expiryKey)
        isConnected = false
        TrackerSync.shared.unregister(id: "myanimelist")
    }

    /// A usable access token, refreshing it first when it is about to expire.
    func validToken() async throws -> String {
        if let token = Keychain.get(Self.accessKey),
           let expiry = UserDefaults.standard.object(forKey: Self.expiryKey) as? Date,
           expiry.timeIntervalSinceNow > 60 { return token }
        if let refreshing { return try await refreshing.value }   // one refresh at a time
        guard let refresh = Keychain.get(Self.refreshKey) else { throw TrackerError.notSignedIn }
        let task = Task { try await requestToken(["grant_type": "refresh_token", "refresh_token": refresh]) }
        refreshing = task
        defer { refreshing = nil }
        do { return try await task.value }
        catch {
            // A rejected refresh token means the user must sign in again.
            if case TrackerError.unauthorized = error { disconnect() }
            throw error
        }
    }

    private func registerTracker() {
        TrackerSync.shared.register(MyAnimeListTracker(auth: self))
    }

    private func requestToken(_ form: [String: String]) async throws -> String {
        var request = URLRequest(url: Self.tokenURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(form.merging(["client_id": clientID]) { current, _ in current })
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400 || status == 401 || status == 403 { throw TrackerError.unauthorized }
        guard (200..<300).contains(status), let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw MyAnimeListAuthError.badResponse
        }
        Keychain.set(token.access_token, for: Self.accessKey)
        Keychain.set(token.refresh_token, for: Self.refreshKey)
        UserDefaults.standard.set(Date().addingTimeInterval(TimeInterval(token.expires_in)), forKey: Self.expiryKey)
        return token.access_token
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
    }

    // MARK: Pure helpers (unit tested)

    /// 43 URL-safe characters, as PKCE requires (43 to 128 from A-Z a-z 0-9 - . _ ~).
    nonisolated static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func authorizeURL(clientID: String, verifier: String, state: String) -> URL {
        var components = URLComponents(string: "https://myanimelist.net/v1/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_challenge", value: verifier),   // "plain" method: challenge == verifier
            URLQueryItem(name: "code_challenge_method", value: "plain"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        return components.url!
    }

    /// The authorization code from `folioreader://mal?code=...&state=...`. Throws if the state differs.
    nonisolated static func code(from url: URL, expectedState: String) throws -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw MyAnimeListAuthError.stateMismatch
        }
        return items.first(where: { $0.name == "code" })?.value
    }

    /// `application/x-www-form-urlencoded` body with every value percent-encoded.
    nonisolated static func formBody(_ fields: [String: String]) -> Data {
        // ASCII only: CharacterSet.alphanumerics also contains accented letters, which must be encoded.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let text = fields.sorted { $0.key < $1.key }.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
        return Data(text.utf8)
    }
}
