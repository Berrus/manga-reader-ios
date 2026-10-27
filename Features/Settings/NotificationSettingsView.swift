import SwiftUI
import UserNotifications
import Observation

enum UpdateNoticeText {
    static func body(count: Int, title: String?, showDetails: Bool) -> String {
        let summary = "\(max(0, count)) new chapter\(count == 1 ? "" : "s") in your library."
        guard showDetails, let title else { return summary }
        return "\(String(title.prefix(150))) — \(summary)"
    }
}

@MainActor @Observable
final class UpdateNotifications {
    static let shared = UpdateNotifications()
    var enabled = UserDefaults.standard.bool(forKey: "notifications.enabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "notifications.enabled") }
    }
    var showDetails = UserDefaults.standard.bool(forKey: "notifications.details") {
        didSet { UserDefaults.standard.set(showDetails, forKey: "notifications.details") }
    }
    private(set) var message: String?
    private(set) var requesting = false
    private let identifier = "folio-library-updates"

    func requestPermission() async {
        guard !requesting else { return }
        requesting = true
        defer { requesting = false }
        do {
            enabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            message = enabled ? "Notifications enabled." : "Notifications are disabled in system Settings."
        } catch { enabled = false; message = error.localizedDescription }
    }
    func disable() {
        enabled = false
        clearHistory()
    }
    func clearHistory() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    func post(count: Int, title: String?, cover: Data?) async {
        guard enabled, count > 0, !Task.isCancelled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard enabled, !Task.isCancelled,
              settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let details = showDetails
        let content = UNMutableNotificationContent()
        content.title = "Library updates"
        content.body = UpdateNoticeText.body(count: count, title: title, showDetails: details)
        content.sound = .default
        var attachmentURL: URL?
        if details, let cover, cover.count <= 30_000_000,
           let jpeg = ImageDownsampler.image(from: cover, maxPixel: 500)?.jpegData(compressionQuality: 0.8) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            attachmentURL = url
            if (try? jpeg.write(to: url, options: .atomic)) != nil,
               let attachment = try? UNNotificationAttachment(identifier: "cover", url: url, options: nil) {
                content.attachments = [attachment]
            }
        }
        defer { if let attachmentURL { try? FileManager.default.removeItem(at: attachmentURL) } }
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            // If disabled while scheduling was suspended, remove the resulting notification too.
            if !enabled { disable() }
            else if details && !showDetails { clearHistory() }
        } catch { message = "Couldn't show update notification: \(error.localizedDescription)" }
    }
}

struct NotificationSettingsView: View {
    @State private var preferences = UpdateNotifications.shared
    var body: some View {
        Form {
            Section {
                if preferences.enabled {
                    Button("Disable update notifications", role: .destructive) { preferences.disable() }
                } else {
                    Button("Enable update notifications") {
                        Task { await preferences.requestPermission() }
                    }.disabled(preferences.requesting)
                }
                Toggle("Show titles and covers", isOn: $preferences.showDetails)
                if let message = preferences.message { Text(message).font(.footnote) }
            } footer: {
                Text("Titles and covers may appear on your lock screen when enabled. Notifications follow successful library checks; background refresh timing is controlled by the system. No push server is used.")
            }
        }.navigationTitle("Notifications")
        .onChange(of: preferences.showDetails) { _, _ in preferences.clearHistory() }
    }
}
