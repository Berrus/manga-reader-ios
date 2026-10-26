import SwiftUI

enum ReaderBackground: String, CaseIterable, Identifiable {
    case black, white, sepia, cover

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .black, .cover: return .black
        case .white: return .white
        case .sepia: return Color(red: 0.96, green: 0.91, blue: 0.80)
        }
    }
}
