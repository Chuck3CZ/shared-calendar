import SwiftUI

/// Everything filed via shake-to-report, newest first — the read side of
/// the pipeline that already pushes a notification when a report lands.
struct AdminBugReportsView: View {
    @State private var reports: [BugReport] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

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
                            Text(relativeDate(report.createdAt))
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
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Bug reporty")
        .refreshable { await load() }
        .task { await load() }
    }

    private func relativeDate(_ raw: String) -> String {
        guard let date = Self.dateFormatter.date(from: raw) else { return raw }
        return date.formatted(.relative(presentation: .named))
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
