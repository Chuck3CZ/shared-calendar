import SwiftUI

/// A 7-day rolling agenda — today through six days out, one section per
/// day. A day with nothing on it still gets a section, with a greyed
/// "Žádná akce" placeholder, so the empty days are visible too.
struct UpcomingView: View {
    @State private var events: [Event] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var detailEvent: Event?
    @State private var editingEvent: Event?

    private static let horizonDays = 7

    private var days: [Date] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return (0..<Self.horizonDays).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfToday) }
    }

    private func events(on day: Date) -> [Event] {
        events
            .filter { Calendar.current.isDate($0.startAt, inSameDayAs: day) }
            .sorted { $0.startAt < $1.startAt }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Dnes" }
        if calendar.isDateInTomorrow(day) { return "Zítra" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(days, id: \.self) { day in
                    let dayEvents = events(on: day)
                    Section(dayTitle(day)) {
                        if dayEvents.isEmpty {
                            Text("Žádná akce")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(dayEvents) { event in
                                Button {
                                    detailEvent = event
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(event.title).font(.headline)
                                            Text(event.startAt.formatted(date: .omitted, time: .shortened))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                            if let location = event.location {
                                                Text(location).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if event.myStatus == "accepted" {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        } else if event.myStatus == "rejected" {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                        }
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Následuje")
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $detailEvent) { event in
                EventDetailView(
                    event: event,
                    onEdit: {
                        detailEvent = nil
                        editingEvent = event
                    },
                    onDeleted: {
                        Task { await load() }
                    }
                )
            }
            .sheet(item: $editingEvent, onDismiss: {
                Task { await load() }
            }) { event in
                NewEventView(eventToEdit: event)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let calendar = Calendar.current
            let from = calendar.startOfDay(for: Date())
            let to = calendar.date(byAdding: .day, value: Self.horizonDays, to: from) ?? from
            events = try await APIClient.shared.fetchEvents(from: from, to: to)
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst akce: \(error.localizedDescription)"
        }
    }
}

#Preview {
    UpcomingView()
}
