import SwiftUI

struct KitsuSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                } footer: {
                    Text("Sent only to Kitsu to sign in. Folio Reader keeps the sign-in token in the Keychain, never your password.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Sign in to Kitsu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Signing in…" : "Sign in") { signIn() }
                        .disabled(busy || email.isEmpty || password.isEmpty)
                }
            }
        }
    }

    private func signIn() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await KitsuAuth.shared.signIn(username: email, password: password)
                password = ""
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
