import SwiftUI
import AuthenticationServices

struct SignInPromptView: View {
    var message = "Přihlas se přes Apple, ať můžeš procházet a reagovat na akce."

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(width: 240, height: 44)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            guard !error.isCancellation else { return }
            errorMessage = "Přihlášení selhalo: \(error.localizedDescription)"
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Přihlášení selhalo: chybí identity token"
                return
            }
            let fullName = credential.fullName.flatMap { components -> String? in
                let formatted = PersonNameComponentsFormatter().string(from: components)
                return formatted.isEmpty ? nil : formatted
            }
            Task {
                do {
                    try await AuthManager.shared.signIn(identityToken: identityToken, fullName: fullName)
                    errorMessage = nil
                } catch {
                    guard !error.isCancellation else { return }
                    errorMessage = "Přihlášení selhalo: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    SignInPromptView()
}
