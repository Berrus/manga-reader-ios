import SwiftUI

/// Wrapped, readable error state for the readers, with an optional retry.
struct ReaderErrorView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(Self.friendly(message))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let retry { Button("Try again", action: retry).buttonStyle(.borderedProminent) }
        }
        .padding(24)
        .frame(maxWidth: 420)
    }

    /// Turns the transport and extension wording into something a reader can act on.
    nonisolated static func friendly(_ message: String) -> String {
        var text = message
        for prefix in ["Extension error: ", "Script error: "] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        guard let range = text.range(of: #"HTTP (\d{3})"#, options: .regularExpression),
              let code = Int(text[range].dropFirst(5)) else { return text }
        switch code {
        case 401, 403: return "The site refused to send this chapter (HTTP \(code)). It may be blocking the app. Try again later."
        case 404, 410: return "This chapter wasn't found (HTTP \(code)). It may have been removed from the site."
        case 429: return "The site is limiting requests (HTTP 429). Wait a minute and try again."
        case 500...599: return "The site is having trouble right now (HTTP \(code)). Try again later."
        default: return text
        }
    }
}
