import SwiftUI
import UIKit

struct ProfileView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var created: [Event] = []
    @State private var responses: [RespondedEvent] = []
    @State private var verificationStatus: VerificationRequest?
    @State private var verificationReason = ""
    @State private var errorMessage: String?
    @State private var didCopyToken = false
    @State private var showingDeleteConfirm = false
    @State private var showingDeleteAccount = false
    @AppStorage("viewAsMember") private var viewAsMember = false

    private var profile: UserProfile? { auth.session?.profile }
    private var accepted: [RespondedEvent] { responses.filter { $0.status == "accepted" } }
    private var rejected: [RespondedEvent] { responses.filter { $0.status == "rejected" } }

    /// The role the rest of the app should behave as — real role, except an
    /// admin with "Testovat jako běžný uživatel" on sees and is gated
    /// exactly like a basic account everywhere outside this screen.
    private var effectiveRole: String? {
        viewAsMember ? "basic" : profile?.role
    }

    private var roleLabel: String {
        switch effectiveRole {
        case "admin": "Administrátor"
        case "verified": "Ověřený uživatel"
        case "basic": "Základní uživatel"
        default: "—"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let commit = Bundle.main.infoDictionary?["GitCommit"] as? String
        guard let commit, !commit.isEmpty else { return "\(version) (\(build))" }
        return "\(version) (\(build)) · \(commit)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if auth.isSignedIn {
                    signedInContent
                } else {
                    SignInPromptView(message: "Přihlas se přes Apple, ať vidíš svůj profil a můžeš vytvářet akce.")
                }
            }
            .navigationTitle("Profil")
        }
    }

    private var signedInContent: some View {
        List {
            Section {
                LabeledContent("Jméno", value: profile?.displayName ?? "—")
                LabeledContent("Role", value: roleLabel)
                Button("Odhlásit se", role: .destructive) { auth.signOut() }
            } footer: {
                if profile?.displayName == nil {
                    Text("Apple posílá jméno appce jen při úplně prvním přihlášení. Pokud chybí, odhlas se, v Nastavení telefonu (Apple ID → Přihlášení a zabezpečení → Aplikace používající Apple ID) u téhle appky zruš přístup a přihlas se znovu — příště už jméno pošle.")
                }
            }

            if profile?.role == "admin" {
                Section {
                    Toggle("Testovat jako běžný uživatel", isOn: $viewAsMember)
                } footer: {
                    Text("Celá appka kromě týhle obrazovky se ti bude ukazovat a chovat, jako bys měl základní účet — admin sekce zmizí, akce půjde jen swipovat/prohlížet, vytváření a mazání se neuloží doopravdy.")
                }

                if !viewAsMember {
                    Section {
                        NavigationLink("Správa uživatelů") {
                            AdminUsersView()
                        }
                        NavigationLink("Bug reporty") {
                            AdminBugReportsView()
                        }
                        NavigationLink("Nahlášené akce") {
                            AdminEventReportsView()
                        }
                    } footer: {
                        Text("Žádosti o ověření nových účtů se schvalují ve Správě uživatelů.")
                    }
                }
            }

            if effectiveRole == "basic" {
                Section {
                    if verificationStatus?.status == "pending" {
                        Text("Žádost čeká na schválení").foregroundStyle(.secondary)
                    } else {
                        TextField("Proč chceš ověřit (nepovinné)", text: $verificationReason)
                        Button("Požádat o ověření") {
                            Task { await requestVerification() }
                        }
                    }
                } header: {
                    Text("Ověření účtu")
                } footer: {
                    Text("Základní účet smí vytvořit nejvýš 2 akce za 14 dní. Ověření tenhle limit odstraní.")
                }
            }

            Section("Vytvořeno mnou (\(created.count))") {
                if created.isEmpty {
                    Text("Zatím žádné akce").foregroundStyle(.secondary)
                } else {
                    ForEach(created) { event in
                        VStack(alignment: .leading) {
                            Text(event.title)
                            Text(event.startAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Zúčastním se (\(accepted.count))") {
                if accepted.isEmpty {
                    Text("Zatím nic").foregroundStyle(.secondary)
                } else {
                    ForEach(accepted) { event in
                        Text(event.title)
                    }
                }
            }

            Section("Nezúčastním se (\(rejected.count))") {
                if rejected.isEmpty {
                    Text("Zatím nic").foregroundStyle(.secondary)
                } else {
                    ForEach(rejected) { event in
                        Text(event.title)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            Section {
                Button {
                    UIPasteboard.general.string = auth.session?.token
                    didCopyToken = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        didCopyToken = false
                    }
                } label: {
                    LabeledContent("Session token") {
                        Text(didCopyToken ? "Zkopírováno" : "•••••••• (klepnutím zkopíruješ)")
                            .font(.caption2)
                            .foregroundStyle(didCopyToken ? .green : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .buttonStyle(.plain)
                LabeledContent("Verze appky", value: appVersion)
                Link("Zásady ochrany osobních údajů", destination: URL(string: "https://sc.gabrhelovi.cz/privacy")!)
            } footer: {
                Text("Klepnutím na token ho zkopíruješ do schránky — hodí se pro ladění přes curl.")
            }

            Section {
                Button("Smazat účet", role: .destructive) {
                    showingDeleteConfirm = true
                }
            } footer: {
                Text("Nenávratně smaže tvůj profil a všechna data k němu vázaná.")
            }
        }
        .refreshable { await load() }
        .onAppear { Task { await load() } }
        .alert("Opravdu chceš smazat účet?", isPresented: $showingDeleteConfirm) {
            Button("Zrušit", role: .cancel) {}
            Button("Pokračovat", role: .destructive) { showingDeleteAccount = true }
        } message: {
            Text("Tahle akce nejde vrátit zpět.")
        }
        .sheet(isPresented: $showingDeleteAccount) {
            DeleteAccountView()
        }
    }

    private func load() async {
        await auth.refreshProfile()
        do {
            async let createdTask = APIClient.shared.fetchCreatedByMe()
            async let responsesTask = APIClient.shared.fetchMyResponses()
            created = try await createdTask
            responses = try await responsesTask
            if effectiveRole == "basic" {
                verificationStatus = try? await APIClient.shared.fetchVerificationStatus()
            }
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst profil: \(error.localizedDescription)"
        }
    }

    private func requestVerification() async {
        // The backend would reject this for a real admin account (it only
        // accepts requests from an actually-basic role) — same "nothing
        // persisted" rule as swiping while testing as a member.
        guard !viewAsMember else {
            verificationStatus = VerificationRequest(
                id: "preview", userId: profile?.id ?? "", reason: verificationReason.isEmpty ? nil : verificationReason,
                status: "pending", createdAt: "", userDisplayName: profile?.displayName
            )
            return
        }
        do {
            verificationStatus = try await APIClient.shared.requestVerification(
                reason: verificationReason.isEmpty ? nil : verificationReason
            )
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se odeslat žádost: \(error.localizedDescription)"
        }
    }

}

#Preview {
    ProfileView()
}
