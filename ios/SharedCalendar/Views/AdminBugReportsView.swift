import SwiftUI

/// Everything filed via shake-to-report, newest first — the read side of
/// the pipeline that already pushes a notification when a report lands.
struct AdminBugReportsView: View {
    @State private var reports: [BugReport] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if reports.isEmpty && !isLoading {
                ContentUnavailableView(
                    "Žádná hlášení",
                    systemImage: "ladybug",
                    description: Text("Zatím nikdo nic nenahlásil")
                )
            } else {
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(report.description)
                        HStack(spacing: 8) {
                            Text(report.userDisplayName ?? "Nepřihlášený")
                            Text("·")
                            Text(ServerDate.relative(report.createdAt))
                            if let appVersion = report.appVersion {
                                Text("· build \(appVersion)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let deviceModel = report.deviceModel, let osVersion = report.osVersion {
                            Text("\(deviceModel) · iOS \(osVersion)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let number = report.githubIssueNumber, let urlString = report.githubIssueUrl, let url = URL(string: urlString) {
                            Link(destination: url) {
                                Label("Issue #\(number)", systemImage: "arrow.up.right.square")
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Bug reporty")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            reports = try await APIClient.shared.fetchBugReports()
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst hlášení: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        AdminBugReportsView()
    }
}
