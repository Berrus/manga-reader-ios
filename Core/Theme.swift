import SwiftUI

enum Theme {
    @MainActor static var accent: Color { AppearancePreferences.shared.palette.color }
    static let cardRadius: CGFloat = 14
    static let coverRadius: CGFloat = 10
    /// Keeps content from stretching edge to edge on iPad and Mac windows.
    static let maxContentWidth: CGFloat = 900
}

/// Cover with a consistent 2:3 shape, soft shadow and a tasteful placeholder.
struct CoverView: View {
    let data: Data?
    var title: String = ""

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: Theme.coverRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.coverRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }

    @ViewBuilder private var content: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [Theme.accent.opacity(0.85), Theme.accent.opacity(0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(title.prefix(1)).uppercased())
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.25), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.04, min(progress, 1)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct Pill: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }
}
