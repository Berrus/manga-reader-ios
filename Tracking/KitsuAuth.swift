import Foundation
import Observation

enum KitsuAuthError: LocalizedError {
    case badCredentials, badResponse

    var errorDescription: String? {
        switch self {
        case .badCredentials: return "Kitsu rejected that email or password."
        case .badResponse: return "Kitsu didn't return a usable sign-in."
        }
    }
}

/// Kitsu signs in with an account email and password. The password is sent once to Kitsu's token
/// endpoint and is never stored; only the access and refresh tokens (Keychain) and the user id are kept.
@MainActor @Observable
final class KitsuAuth {
    static let shared = KitsuAuth()

    private static let accessKey = "kitsu.access"
    private static let refreshKey = "kitsu.refresh"
    private static let userKey = "kitsu.user"
    private static let expiryKey = "kitsu.expiry"
    private static let tokenURL = URL(string: "https://kitsu.io/api/oauth/token")!
    private static let usersURL = URL(string: "https://kitsu.io/api/edge/users?filter%5Bself%5D=true")!

    private(set) var isConnected = Keychain.get(KitsuAuth.refreshKey) != nil
    @ObservationIgnored private var refreshing: Task<String, Error>?

    var userID: String? { Keychain.get(Self.userKey) }

    func restore() {
        isConnected = Keychain.get(Self.refreshKey) != nil
        if isConnected { registerTracker() }
    }

    func signIn(username: String, password: String) async throws {
        let token = try await requestToken(["grant_type": "password", "username": username, "password": password])
        Keychain.set(try await fetchUserID(token: token), for: Self.userKey)
        isConnected = true
        registerTracker()
    }

    func signOut() {
        [Self.accessKey, Self.refreshKey, Self.userKey].forEach(Keychain.remove)
        UserDefaults.standard.removeObject(forKey: Self.expiryKey)
        isConnected = false
        TrackerSync.shared.unregister(id: "kitsu")
    }

    /// A usable access token, refreshed first when it is about to expire.
    func validToken() async throws -> String {
        if let token = Keychain.get(Self.accessKey),
           let expiry = UserDefaults.standard.object(forKey: Self.expiryKey) as? Date,
           expiry.timeIntervalSinceNow > 60 { return token }
        if let refreshing { return try await refreshing.value }
        guard let refresh = Keychain.get(Self.refreshKey) else { throw TrackerError.notSignedIn }
        let task = Task { try await requestToken(["grant_type": "refresh_token", "refresh_token": refresh]) }
        refreshing = task
        defer { refreshing = nil }
        do { return try await task.value }
        catch {
            if case KitsuAuthError.badCredentials = error { signOut() }   // refresh token no longer valid
            throw error
        }
    }

    private func registerTracker() { TrackerSync.shared.register(KitsuTracker(auth: self)) }

    private func requestToken(_ form: [String: String]) async throws -> String {
        var request = URLRequest(url: Self.tokenURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = MyAnimeListAuth.formBody(form)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400 || status == 401 || status == 403 { throw KitsuAuthError.badCredentials }
        guard (200..<300).contains(status), let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw KitsuAuthError.badResponse
        }
        Keychain.set(token.access_token, for: Self.accessKey)
        Keychain.set(token.refresh_token, for: Self.refreshKey)
        UserDefaults.standard.set(Date().addingTimeInterval(TimeInterval(token.expires_in)), forKey: Self.expiryKey)
        return token.access_token
    }

    private func fetchUserID(token: String) async throws -> String {
        var request = URLRequest(url: Self.usersURL, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let id = Self.userID(from: data) else { throw KitsuAuthError.badResponse }
        return id
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
    }

    nonisolated static func userID(from data: Data) -> String? {
        struct Users: Decodable { struct User: Decodable { let id: String }; let data: [User] }
        return (try? JSONDecoder().decode(Users.self, from: data))?.data.first?.id
    }
}
