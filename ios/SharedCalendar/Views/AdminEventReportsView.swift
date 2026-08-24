import SwiftUI

/// Everything filed via "Nahlásit akci", newest first. Removing the
/// offending event reuses the same delete endpoint an admin already has
/// for any event — no separate moderation action needed server-side.
struct AdminEventReportsView: View {
    @State private var reports: [EventReport] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var deletingEventId: String?

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
                    systemImage: "flag",
                    description: Text("Zatím nikdo nic nenahlásil")
                )
            } else {
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(report.eventTitle)
                                .font(.headline)
                                .strikethrough(report.eventDeletedAt != nil)
                            if report.eventDeletedAt != nil {
                                Text("smazáno").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Text(report.reason)
                        HStack(spacing: 8) {
                            Text(report.reporterDisplayName ?? "Neznámý")
                            Text("·")
                            Text(relativeDate(report.createdAt))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if report.eventDeletedAt == nil {
                            Button("Smazat nahlášenou akci", role: .destructive) {
                                Task { await deleteEvent(report.eventId) }
                            }
                            .font(.caption)
                            .disabled(deletingEventId == report.eventId)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Nahlášené akce")
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
            reports = try await APIClient.shared.fetchEventReports()
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst hlášení: \(error.localizedDescription)"
        }
    }

    private func deleteEvent(_ eventId: String) async {
        deletingEventId = eventId
        defer { deletingEventId = nil }
        do {
            try await APIClient.shared.deleteEvent(id: eventId)
            await load()
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se smazat akci: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        AdminEventReportsView()
    }
}
