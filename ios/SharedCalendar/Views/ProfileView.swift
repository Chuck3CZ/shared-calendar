import SwiftUI

struct ProfileView: View {
    @State private var profile: UserProfile?
    @State private var created: [Event] = []
    @State private var responses: [RespondedEvent] = []
    @State private var errorMessage: String?
    @AppStorage("viewAsMember") private var viewAsMember = false

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
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Účet") {
                    LabeledContent("Role", value: roleLabel)
                    LabeledContent("Client ID") {
                        Text(profile?.clientId ?? ClientIdentity.current)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }

                if profile?.role == "admin" {
                    Section {
                        Toggle("Testovat jako běžný uživatel", isOn: $viewAsMember)
                    } footer: {
                        Text("Dočasně tě to ve swipe okně vrátí do role základního uživatele, aniž bys musel přepínat účty.")
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
                    LabeledContent("Verze appky", value: appVersion)
                }
            }
            .navigationTitle("Profil")
            .refreshable { await load() }
            .onAppear { Task { await load() } }
        }
    }

    private func load() async {
        do {
            async let profileTask = APIClient.shared.fetchMe()
            async let createdTask = APIClient.shared.fetchCreatedByMe()
            async let responsesTask = APIClient.shared.fetchMyResponses()
            profile = try await profileTask
            created = try await createdTask
            responses = try await responsesTask
            errorMessage = nil
        } catch {
            errorMessage = "Nepodařilo se načíst profil: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ProfileView()
}
