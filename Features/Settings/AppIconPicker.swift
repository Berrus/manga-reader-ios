import SwiftUI
import UIKit

enum AppIconChoice: String, CaseIterable, Identifiable {
    case indigo, ink, coral, light

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// nil selects the primary icon.
    var iconName: String? {
        switch self {
        case .indigo: return nil
        case .ink: return "AppIcon-Ink"
        case .coral: return "AppIcon-Coral"
        case .light: return "AppIcon-Light"
        }
    }

    var preview: String { "IconPreview-\(title)" }

    static func current() -> AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .indigo
    }
}

struct AppIconPicker: View {
        @State private var selected = AppIconChoice.current()
    @State private var errorMessage: String?
    @State private var isChanging = false

    private var isSupported: Bool { UIApplication.shared.supportsAlternateIcons }

    var body: some View {
        if isSupported { picker } else { unsupported }
    }

    /// Mac Catalyst never supports alternate icons; on iOS it means the build didn't declare them.
    private var unsupported: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image("IconPreview-Indigo").resizable().frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            #if targetEnvironment(macCatalyst)
            Text("Alternate icons aren't available in the Mac app.")
            #else
            Text("Alternate icons aren't available in this build. Rebuild with `xcodegen generate` so the icon sets are registered.")
            #endif
        }
        .font(.footnote).foregroundStyle(.secondary)
    }

    private var picker: some View {
        HStack(spacing: 14) {
            ForEach(AppIconChoice.allCases) { choice in
                Button { select(choice) } label: {
                    VStack(spacing: 6) {
                        Image(choice.preview)
                            .resizable()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(selected == choice ? Theme.accent : .primary.opacity(0.1),
                                                  lineWidth: selected == choice ? 3 : 0.5)
                            }
                        Text(choice.title).font(.caption)
                            .foregroundStyle(selected == choice ? Theme.accent : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isChanging)
                .accessibilityLabel("\(choice.title) icon")
                .accessibilityAddTraits(selected == choice ? .isSelected : [])
            }
        }
                .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .onAppear { selected = AppIconChoice.current() }
        .alert("Couldn't change icon", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func select(_ choice: AppIconChoice) {
        guard choice != selected, !isChanging else { return }
        isChanging = true
        Task {
            defer { isChanging = false }
            do {
                try await Self.apply(choice.iconName)
                selected = choice
            } catch {
                let code = (error as NSError).code
                errorMessage = "\(error.localizedDescription) (code \(code)). Icon: \(choice.iconName ?? "primary")"
            }
        }
    }

    /// iOS answers "resource temporarily unavailable" (POSIX error 35) when a change lands while the
    /// app is mid-transition (a menu or alert closing, app not yet active) or another change is still
    /// in flight. Waiting until the app is active and retrying a few times clears it.
    private static func apply(_ name: String?) async throws {
        var attempt = 0
        while true {
            if UIApplication.shared.applicationState != .active {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                return
            } catch let error as NSError where isTransient(error) && attempt < 3 {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
            }
        }
    }

    static func isTransient(_ error: NSError) -> Bool {
        error.domain == NSPOSIXErrorDomain && error.code == 35
    }
}
