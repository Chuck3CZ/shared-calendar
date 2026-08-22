import SwiftUI

struct CalendarView: View {
    @State private var selectedDate = Date()
    @State private var events: [Event] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var eventsForSelectedDay: [Event] {
        events
            .filter { Calendar.current.isDate($0.startAt, inSameDayAs: selectedDate) }
            .sorted { $0.startAt < $1.startAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("Datum", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)

                List {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else if eventsForSelectedDay.isEmpty {
                        Text("Žádné akce tento den").foregroundStyle(.secondary)
                    } else {
                        ForEach(eventsForSelectedDay) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title).font(.headline)
                                Text(event.startAt.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let location = event.location {
                                    Text(location).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kalendář")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let calendar = Calendar.current
            let from = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            let to = calendar.date(byAdding: .month, value: 3, to: Date()) ?? Date()
            events = try await APIClient.shared.fetchEvents(from: from, to: to)
            errorMessage = nil
        } catch {
            errorMessage = "Nepodařilo se načíst akce: \(error.localizedDescription)"
        }
    }
}

#Preview {
    CalendarView()
}
