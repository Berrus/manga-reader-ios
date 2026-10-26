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

    var body: some View {
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
                .accessibilityLabel("\(choice.title) icon")
                .accessibilityAddTraits(selected == choice ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .alert("Couldn't change icon", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func select(_ choice: AppIconChoice) {
        guard choice != selected else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(choice.iconName)
                selected = choice
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
