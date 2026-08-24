import SwiftUI

/// Sheet behind the bell icon — everything that has ever been pushed to
/// this user, newest first. Marks everything read as soon as it's opened.
struct NotificationHistoryView: View {
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var detailEvent: Event?
    @State private var showingClearAllConfirm = false
    @State private var didDelete = false
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
                    List {
                        ForEach(notifications) { item in
                            let eventGone = item.eventDeletedAt != nil
                            Button {
                                guard let eventId = item.eventId, !eventGone else { return }
                                Task { detailEvent = try? await APIClient.shared.fetchEvent(id: eventId) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.headline)
                                    Text(item.body).font(.subheadline).foregroundStyle(.secondary)
                                    HStack(spacing: 6) {
                                        Text(relativeDate(item.createdAt))
                                        if eventGone {
                                            Text("· akce smazána")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(eventGone ? .secondary : .primary)
                            .swipeActions {
                                Button("Smazat", role: .destructive) {
                                    Task { await delete(item) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Notifikace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
                if !notifications.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Vymazat vše", role: .destructive) {
                            showingClearAllConfirm = true
                        }
                    }
                }
            }
            .confirmationDialog("Vymazat všechny notifikace?", isPresented: $showingClearAllConfirm, titleVisibility: .visible) {
                Button("Vymazat vše", role: .destructive) {
                    Task { await clearAll() }
                }
            }
            .sheet(item: $detailEvent) { event in
                EventDetailView(event: event)
            }
            .task { await load() }
            .sensoryFeedback(.impact(weight: .light), trigger: didDelete)
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

    private func delete(_ item: AppNotification) async {
        // Removed from the list right away — a failed delete just leaves it
        // there after the next load rather than needing a rollback dance.
        notifications.removeAll { $0.id == item.id }
        didDelete = true
        do {
            try await APIClient.shared.deleteNotification(id: item.id)
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se smazat notifikaci: \(error.localizedDescription)"
        }
    }

    private func clearAll() async {
        let previous = notifications
        notifications = []
        didDelete = true
        do {
            try await APIClient.shared.clearNotifications()
        } catch {
            guard !error.isCancellation else { return }
            notifications = previous
            errorMessage = "Nepodařilo se vymazat notifikace: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NotificationHistoryView()
}
