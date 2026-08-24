import SwiftUI

/// Everyone who's ever signed in, with their current role and a menu to
/// change it directly, plus the pending verification queue up top — both
/// live here so an admin has one place for anything role-related.
struct AdminUsersView: View {
    @State private var users: [AdminUser] = []
    @State private var pendingRequests: [VerificationRequest] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private static let roles: [(value: String, label: String)] = [
        ("basic", "Základní"),
        ("verified", "Ověřený"),
        ("admin", "Administrátor"),
    ]

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
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

            ForEach(users) { user in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(user.displayName ?? "Bez jména")
                            .font(.headline)
                            .verifiedBadge(role: user.role)
                        Spacer()
                        Menu(label(for: user.role)) {
                            ForEach(Self.roles, id: \.value) { role in
                                Button(role.label) {
                                    Task { await setRole(user, to: role.value) }
                                }
                            }
                        }
                        .font(.subheadline)
                    }
                    if let status = user.latestVerificationStatus {
                        Text("Poslední žádost o ověření: \(verificationStatusLabel(status))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Uživatelé")
        .refreshable { await load() }
        .task { await load() }
    }

    private func label(for role: String) -> String {
        Self.roles.first { $0.value == role }?.label ?? role
    }

    private func verificationStatusLabel(_ status: String) -> String {
        switch status {
        case "pending": "čeká"
        case "approved": "schváleno"
        case "rejected": "zamítnuto"
        default: status
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let usersTask = APIClient.shared.fetchAllUsers()
            async let requestsTask = APIClient.shared.fetchPendingVerificationRequests()
            users = try await usersTask
            pendingRequests = try await requestsTask
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst uživatele: \(error.localizedDescription)"
        }
    }

    private func setRole(_ user: AdminUser, to role: String) async {
        do {
            let updated = try await APIClient.shared.setUserRole(id: user.id, role: role)
            if let index = users.firstIndex(where: { $0.id == user.id }) {
                users[index] = updated
            }
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se změnit roli: \(error.localizedDescription)"
        }
    }

    private func approve(_ request: VerificationRequest) async {
        do {
            try await APIClient.shared.approveVerificationRequest(id: request.id)
            pendingRequests.removeAll { $0.id == request.id }
            await load()
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
    NavigationStack {
        AdminUsersView()
    }
}
