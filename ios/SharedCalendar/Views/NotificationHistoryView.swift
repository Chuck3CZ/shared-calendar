import SwiftUI

/// Sheet behind the bell icon — everything that has ever been pushed to
/// this user, newest first. Marks everything read as soon as it's opened.
struct NotificationHistoryView: View {
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var detailEvent: Event?
    @Environment(\.dismiss) private var dismiss

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).padding()
                } else if notifications.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "Zatím žádné notifikace",
                        systemImage: "bell",
                        description: Text("Tady se objeví, až ti něco přijde")
                    )
                } else {
                    List(notifications) { item in
                        Button {
                            guard let eventId = item.eventId else { return }
                            Task { detailEvent = try? await APIClient.shared.fetchEvent(id: eventId) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline)
                                Text(item.body).font(.subheadline).foregroundStyle(.secondary)
                                Text(relativeDate(item.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Notifikace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
            .sheet(item: $detailEvent) { event in
                EventDetailView(event: event)
            }
            .task { await load() }
        }
    }

    private func relativeDate(_ raw: String) -> String {
        guard let date = Self.displayFormatter.date(from: raw) else { return raw }
        return date.formatted(.relative(presentation: .named))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            notifications = try await APIClient.shared.fetchNotifications()
            errorMessage = nil
            try? await APIClient.shared.markNotificationsRead()
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst notifikace: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NotificationHistoryView()
}
