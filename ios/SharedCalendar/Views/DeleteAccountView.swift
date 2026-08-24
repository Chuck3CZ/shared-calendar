import SwiftUI

/// Reachable from ProfileView after the "Opravdu chceš smazat účet?" alert
/// is confirmed — requires a second, deliberate slide-to-confirm before
/// anything is sent, mirroring the same pattern used for deleting an event.
struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthManager.shared

    private enum Step: Int, CaseIterable {
        case data, account, signOut

        var label: String {
            switch self {
            case .data: "Mažu tvoje data"
            case .account: "Mažu účet"
            case .signOut: "Odhlašuju tě"
            }
        }
    }

    @State private var currentStep: Step?
    @State private var didFinish = false
    @State private var errorMessage: String?
    // Read by SignInPromptView once signed out, so the "revoke access in
    // Settings first" reminder survives past this sheet closing — persisted
    // (not just in-memory) so it's still there even after the app relaunches.
    @AppStorage("justDeletedAccount") private var justDeletedAccount = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)

                Text("Smažeme tvůj profil, vlastní akce, odpovědi na akce i historii upozornění. Tohle nejde vrátit zpět.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if currentStep == nil {
                    Text("Přihlásíš se znovu stejným Apple ID? Apple appce jméno pošle jen napoprvé — tobě ho už jednou poslalo, takže při novém přihlášení zůstane prázdné, dokud appce nezrušíš přístup v Nastavení telefonu (Apple ID → Přihlášení a zabezpečení → Aplikace používající Apple ID).")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal)
                }

                if let currentStep {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Step.allCases, id: \.self) { step in
                            HStack(spacing: 10) {
                                if step.rawValue < currentStep.rawValue {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                } else if step == currentStep {
                                    ProgressView()
                                } else {
                                    Image(systemName: "circle").foregroundStyle(.tertiary)
                                }
                                Text(step.label)
                                    .foregroundStyle(step.rawValue <= currentStep.rawValue ? .primary : .secondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                    .padding(.horizontal)
                } else {
                    SlideToConfirmView(label: "Přejetím smažeš účet natrvalo") {
                        await performDelete()
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red).padding(.horizontal)
                    }
                }

                Spacer()
            }
            .padding(.top, 32)
            .navigationTitle("Smazat účet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                        .disabled(currentStep != nil)
                }
            }
            .interactiveDismissDisabled(currentStep != nil)
            .sensoryFeedback(.success, trigger: didFinish)
        }
    }

    private func performDelete() async {
        errorMessage = nil
        currentStep = .data
        try? await Task.sleep(for: .seconds(0.5))
        do {
            currentStep = .account
            try await APIClient.shared.deleteAccount()
            currentStep = .signOut
            try? await Task.sleep(for: .seconds(0.4))
            justDeletedAccount = true
            auth.signOut()
            didFinish = true
            try? await Task.sleep(for: .seconds(0.6))
            dismiss()
        } catch {
            errorMessage = "Nepodařilo se smazat účet: \(error.localizedDescription)"
            currentStep = nil
        }
    }
}

#Preview {
    DeleteAccountView()
}
