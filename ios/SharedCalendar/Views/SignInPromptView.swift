import SwiftUI
import AuthenticationServices
import UIKit

struct SignInPromptView: View {
    var message = "Přihlas se přes Apple, ať můžeš procházet a reagovat na akce."

    @State private var errorMessage: String?
    // Set by DeleteAccountView right before it signs out — stays true
    // (survives an app relaunch, since it's persisted, not just in-memory)
    // until a sign-in actually succeeds, so the reminder can't be missed.
    @AppStorage("justDeletedAccount") private var justDeletedAccount = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            if justDeletedAccount {
                VStack(spacing: 10) {
                    Text("Účet byl nedávno smazán. Aby se při přihlášení stejným Apple ID znovu propsalo jméno, nejdřív appce zruš přístup v Nastavení (Apple ID → Přihlášení a zabezpečení → Aplikace používající Apple ID → SharedCalendar → Zastavit používání Apple ID) a teprve pak se přihlas znovu tady dole.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Otevřít Nastavení") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .font(.caption.bold())
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
                .padding(.horizontal, 24)
            }

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
                    justDeletedAccount = false
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
