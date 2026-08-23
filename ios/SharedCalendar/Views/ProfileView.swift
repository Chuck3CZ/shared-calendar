import SwiftUI
import UIKit

struct ProfileView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var created: [Event] = []
    @State private var responses: [RespondedEvent] = []
    @State private var verificationStatus: VerificationRequest?
    @State private var pendingRequests: [VerificationRequest] = []
    @State private var verificationReason = ""
    @State private var errorMessage: String?
    @State private var didCopyToken = false
    @AppStorage("viewAsMember") private var viewAsMember = false

    private var profile: UserProfile? { auth.session?.profile }
    private var accepted: [RespondedEvent] { responses.filter { $0.status == "accepted" } }
    private var rejected: [RespondedEvent] { responses.filter { $0.status == "rejected" } }

    private var roleLabel: String {
        switch profile?.role {
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
                    Text("Dočasně tě to ve swipe okně vrátí do role základního uživatele, aniž bys musel přepínat účty.")
                }

                Section {
                    NavigationLink("Správa uživatelů") {
                        AdminUsersView()
                    }
                    NavigationLink("Bug reporty") {
                        AdminBugReportsView()
                    }
                }

                Section("Žádosti o ověření (\(pendingRequests.count))") {
                    if pendingRequests.isEmpty {
                        Text("Žádné čekající žádosti").foregroundStyle(.secondary)
                    } else {
                        ForEach(pendingRequests) { request in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(request.userDisplayName ?? "Bez jména").font(.headline)
                                if let reason = request.reason, !reason.isEmpty {
                                    Text(reason).font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Button("Zamítnout", role: .destructive) {
                                        Task { await reject(request) }
                                    }
                                    Spacer()
                                    Button("Schválit") {
                                        Task { await approve(request) }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if profile?.role == "basic" {
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
                        Text(didCopyToken ? "Zkopírováno" : (auth.session?.token ?? ""))
                            .font(.caption2)
                            .foregroundStyle(didCopyToken ? .green : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .buttonStyle(.plain)
                LabeledContent("Verze appky", value: appVersion)
            } footer: {
                Text("Klepnutím na token ho zkopíruješ do schránky — hodí se pro ladění přes curl.")
            }
        }
        .refreshable { await load() }
        .onAppear { Task { await load() } }
    }

    private func load() async {
        await auth.refreshProfile()
        do {
            async let createdTask = APIClient.shared.fetchCreatedByMe()
            async let responsesTask = APIClient.shared.fetchMyResponses()
            created = try await createdTask
            responses = try await responsesTask
            if profile?.role == "basic" {
                verificationStatus = try? await APIClient.shared.fetchVerificationStatus()
            }
            if profile?.role == "admin" {
                pendingRequests = (try? await APIClient.shared.fetchPendingVerificationRequests()) ?? []
            }
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst profil: \(error.localizedDescription)"
        }
    }

    private func requestVerification() async {
        do {
            verificationStatus = try await APIClient.shared.requestVerification(
                reason: verificationReason.isEmpty ? nil : verificationReason
            )
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se odeslat žádost: \(error.localizedDescription)"
        }
    }

    private func approve(_ request: VerificationRequest) async {
        do {
            try await APIClient.shared.approveVerificationRequest(id: request.id)
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se schválit žádost: \(error.localizedDescription)"
        }
    }

    private func reject(_ request: VerificationRequest) async {
        do {
            try await APIClient.shared.rejectVerificationRequest(id: request.id)
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se zamítnout žádost: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ProfileView()
}
