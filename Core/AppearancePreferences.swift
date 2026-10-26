import SwiftUI
import Observation

enum AppPalette: String, CaseIterable, Identifiable {
    case violet, ocean, mint, coral, rose
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .violet: return Color(red: 0.43, green: 0.36, blue: 0.95)
        case .ocean: return Color(red: 0.04, green: 0.47, blue: 0.85)
        case .mint: return Color(red: 0.05, green: 0.56, blue: 0.39)
        case .coral: return Color(red: 0.87, green: 0.24, blue: 0.24)
        case .rose: return Color(red: 0.75, green: 0.22, blue: 0.56)
        }
    }
}

@MainActor @Observable
final class AppearancePreferences {
    static let shared = AppearancePreferences()
    var palette: AppPalette {
        didSet { UserDefaults.standard.set(palette.rawValue, forKey: "appearance.palette") }
    }
    init() {
        palette = AppPalette(rawValue: UserDefaults.standard.string(forKey: "appearance.palette") ?? "") ?? .violet
    }
}

struct AppearanceSettingsView: View {
    @State private var preferences = AppearancePreferences.shared
    var body: some View {
        Form {
            Section("Accent color") {
                ForEach(AppPalette.allCases) { palette in
                    Button {
                        preferences.palette = palette
                    } label: {
                        HStack {
                            Circle().fill(palette.color).frame(width: 24, height: 24)
                            Text(palette.label).foregroundStyle(.primary)
                            Spacer()
                            if preferences.palette == palette { Image(systemName: "checkmark") }
                        }
                    }
                    .accessibilityLabel(palette.label)
                    .accessibilityValue(preferences.palette == palette ? "Selected" : "Not selected")
                }
            }
        }
        .navigationTitle("Appearance")
    }
}
