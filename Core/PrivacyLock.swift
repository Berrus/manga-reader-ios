import LocalAuthentication
import Observation

/// Opens and closes access to private categories. Locks again whenever the app leaves the foreground.
@MainActor @Observable
final class PrivacyLock {
    static let shared = PrivacyLock()

    private(set) var isUnlocked = false

    /// Private categories need a device passcode or biometrics to be meaningful.
    var canProtect: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    @discardableResult
    func unlock(reason: String = "Show your private categories") async -> Bool {
        if isUnlocked { return true }
        do { isUnlocked = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { isUnlocked = false }
        return isUnlocked
    }

    func lock() { isUnlocked = false }
}

enum PrivacyFilter {
    /// Series in a private category are left out while the lock is closed.
    static func visible(_ items: [Manga], categories: [Category], unlocked: Bool) -> [Manga] {
        guard !unlocked else { return items }
        let hidden = Set(categories.filter(\.isPrivate).map(\.id))
        guard !hidden.isEmpty else { return items }
        return items.filter { $0.categoryID.map(hidden.contains) != true }
    }

    static func privateCategoryIDs(_ categories: [Category]) -> Set<UUID> {
        Set(categories.filter(\.isPrivate).map(\.id))
    }
}
