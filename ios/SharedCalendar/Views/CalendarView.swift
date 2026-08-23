import SwiftUI
import MapKit

func openInMaps(latitude: Double, longitude: Double, name: String) {
    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let placemark = MKPlacemark(coordinate: coordinate)
    let mapItem = MKMapItem(placemark: placemark)
    mapItem.name = name
    mapItem.openInMaps()
}

struct CalendarView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var selectedDate = Date()
    @State private var events: [Event] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingNewEvent = false
    @State private var editingEvent: Event?
    @State private var detailEvent: Event?
    @AppStorage("viewAsMember") private var viewAsMember = false

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
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else if event.myStatus == "rejected" {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Kalendář")
            .toolbar {
                if auth.isSignedIn && !viewAsMember {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingNewEvent = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewEvent, onDismiss: {
                Task { await load() }
            }) {
                NewEventView()
            }
            .sheet(item: $editingEvent, onDismiss: {
                Task { await load() }
            }) { event in
                NewEventView(eventToEdit: event)
            }
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
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst akce: \(error.localizedDescription)"
        }
    }
}

private struct EventDetailView: View {
    let event: Event
    let onEdit: () -> Void
    let onDeleted: () -> Void

    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false
    @State private var showingSlideToDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var reminderMinutes: [Int] = []

    private var isOwner: Bool { auth.session?.profile.id == event.ownerId }
    private var isAdmin: Bool { auth.session?.profile.role == "admin" }
    private var isAttending: Bool { event.myStatus == "accepted" }

    private static let reminderOptions: [(label: String, minutes: Int)] = [
        ("V čas akce", 0),
        ("10 minut předem", 10),
        ("30 minut předem", 30),
        ("Hodinu předem", 60),
        ("2 hodiny předem", 120),
        ("Den předem", 1440),
    ]

    private var firstReminderBinding: Binding<Int?> {
        Binding(
            get: { reminderMinutes.first },
            set: { newValue in
                reminderMinutes = newValue.map { [$0] } ?? []
                Task { await saveReminders() }
            }
        )
    }

    private var secondReminderBinding: Binding<Int?> {
        Binding(
            get: { reminderMinutes.count > 1 ? reminderMinutes[1] : nil },
            set: { newValue in
                guard !reminderMinutes.isEmpty else { return }
                if let newValue {
                    if reminderMinutes.count > 1 { reminderMinutes[1] = newValue } else { reminderMinutes.append(newValue) }
                } else if reminderMinutes.count > 1 {
                    reminderMinutes.removeLast()
                }
                Task { await saveReminders() }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Akce") {
                    LabeledContent("Název", value: event.title)
                    if let description = event.description, !description.isEmpty {
                        LabeledContent("Popis", value: description)
                    }
                    if let location = event.location, !location.isEmpty {
                        LabeledContent("Místo", value: location)
                    }
                    LabeledContent("Kdy", value: event.startAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Autor", value: isOwner ? "Ty" : (event.ownerName ?? "Neznámé jméno"))
                    if let latitude = event.latitude, let longitude = event.longitude {
                        WeatherSummaryView(latitude: latitude, longitude: longitude, date: event.startAt)
                        Button("Otevřít v Mapách") {
                            openInMaps(latitude: latitude, longitude: longitude, name: event.location ?? event.title)
                        }
                    }
                }

                if isAttending {
                    Section {
                        Picker("První upozornění", selection: firstReminderBinding) {
                            Text("Žádné").tag(Int?.none)
                            ForEach(Self.reminderOptions, id: \.minutes) { option in
                                Text(option.label).tag(Int?.some(option.minutes))
                            }
                        }
                        if reminderMinutes.first != nil {
                            Picker("Druhé upozornění", selection: secondReminderBinding) {
                                Text("Žádné").tag(Int?.none)
                                ForEach(Self.reminderOptions.filter { $0.minutes != reminderMinutes.first }, id: \.minutes) { option in
                                    Text(option.label).tag(Int?.some(option.minutes))
                                }
                            }
                        }
                    } header: {
                        Text("Upozornění")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                if showingSlideToDelete {
                    Section {
                        SlideToConfirmView(label: "Přejetím přesuneš akci do koše") {
                            await performDelete()
                        }
                        Button("Zrušit mazání") {
                            withAnimation { showingSlideToDelete = false }
                        }
                        .disabled(isDeleting)
                    }
                } else {
                    Section {
                        if isOwner {
                            Button("Upravit") { onEdit() }
                        }
                        if isOwner || isAdmin {
                            Button("Smazat", role: .destructive) {
                                showingDeleteConfirm = true
                            }
                        }
                    }
                }
            }
            .navigationTitle("Detail akce")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
            .alert("Opravdu chcete smazat?", isPresented: $showingDeleteConfirm) {
                Button("Zrušit", role: .cancel) {}
                Button("Smazat", role: .destructive) {
                    withAnimation { showingSlideToDelete = true }
                }
            } message: {
                Text("Akce se přesune do koše.")
            }
            .task { await loadReminders() }
        }
    }

    private func loadReminders() async {
        guard isAttending else { return }
        do {
            let settings = try await APIClient.shared.fetchReminders(eventId: event.id)
            reminderMinutes = settings.minutes
        } catch {
            // Non-fatal: reminder section just starts empty.
        }
    }

    private func saveReminders() async {
        do {
            try await APIClient.shared.setReminders(eventId: event.id, minutes: reminderMinutes)
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se uložit upozornění: \(error.localizedDescription)"
        }
    }

    private func performDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await APIClient.shared.deleteEvent(id: event.id)
            onDeleted()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se smazat akci: \(error.localizedDescription)"
            withAnimation { showingSlideToDelete = false }
        }
    }
}

/// A "slide to confirm" control, similar to iOS's slide-to-power-off, used as
/// a deliberate second confirmation before a destructive action actually runs.
private struct SlideToConfirmView: View {
    let label: String
    let onConfirm: () async -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isConfirming = false
    @State private var trackWidth: CGFloat = 280
    private let thumbSize: CGFloat = 44

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.red.opacity(0.15))
                .frame(height: thumbSize)
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, thumbSize)
            Circle()
                .fill(Color.red)
                .frame(width: thumbSize, height: thumbSize)
                .overlay {
                    if isConfirming {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "chevron.right.2")
                            .foregroundStyle(.white)
                    }
                }
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !isConfirming else { return }
                            let maxOffset = max(trackWidth - thumbSize, 0)
                            dragOffset = min(max(0, value.translation.width), maxOffset)
                        }
                        .onEnded { _ in
                            guard !isConfirming else { return }
                            let maxOffset = max(trackWidth - thumbSize, 0)
                            if maxOffset > 0 && dragOffset > maxOffset * 0.85 {
                                dragOffset = maxOffset
                                isConfirming = true
                                Task { await onConfirm() }
                            } else {
                                withAnimation(.spring) { dragOffset = 0 }
                            }
                        }
                )
        }
        .frame(height: thumbSize)
        .background(
            GeometryReader { proxy in
                Color.clear.onAppear { trackWidth = proxy.size.width }
            }
        )
        .listRowInsets(EdgeInsets())
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

#Preview {
    CalendarView()
}
