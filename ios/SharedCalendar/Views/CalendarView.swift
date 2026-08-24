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
    @State private var showingNotifications = false
    @State private var editingEvent: Event?
    @State private var detailEvent: Event?
    @AppStorage("viewAsMember") private var viewAsMember = false
    @Environment(\.scenePhase) private var scenePhase
    // The graphical DatePicker (backed by UICalendarView) has a known bug
    // where a day's number can render blank after the app returns from the
    // background, only fixing itself once that cell is interacted with.
    // Forcing SwiftUI to recreate it on foreground works around that.
    @State private var datePickerRefreshID = UUID()
    // The window actually fetched — selectedDate can wander anywhere via
    // the graphical DatePicker, well outside it, so it needs tracking to
    // know when a refetch centered on the new date is actually due.
    @State private var loadedFrom: Date?
    @State private var loadedTo: Date?

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
                    .id(datePickerRefreshID)

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
                if auth.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingNotifications = true
                        } label: {
                            Image(systemName: "bell")
                        }
                        .accessibilityLabel("Historie notifikací")
                    }
                }
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
            .sheet(isPresented: $showingNotifications) {
                NotificationHistoryView()
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
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                datePickerRefreshID = UUID()
            }
            .onChange(of: selectedDate) { _, newDate in
                guard let loadedFrom, let loadedTo, !(loadedFrom...loadedTo).contains(newDate) else { return }
                Task { await load(around: newDate) }
            }
        }
    }

    private func load(around referenceDate: Date = Date()) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let calendar = Calendar.current
            let from = calendar.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate
            let to = calendar.date(byAdding: .month, value: 3, to: referenceDate) ?? referenceDate
            events = try await APIClient.shared.fetchEvents(from: from, to: to)
            loadedFrom = from
            loadedTo = to
            errorMessage = nil
            WidgetDataStore.update(from: events)
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst akce: \(error.localizedDescription)"
        }
    }
}

struct EventDetailView: View {
    let event: Event
    var onEdit: () -> Void = {}
    var onDeleted: () -> Void = {}

    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false
    @State private var showingSlideToDelete = false
    @State private var didDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var reminderMinutes: [Int] = []
    @State private var showingReportEvent = false

    private var isOwner: Bool { auth.session?.profile.id == event.ownerId }
    private var isAdmin: Bool { auth.session?.profile.role == "admin" }
    private var isAttending: Bool { event.myStatus == "accepted" }

    /// A universal link — opens straight to this event's detail in the app
    /// for anyone who has it installed, or a plain web page otherwise.
    private var shareURL: URL {
        APIClient.shared.baseURL.appendingPathComponent("event").appendingPathComponent(event.id)
    }

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
                    if let endAt = event.endAt {
                        LabeledContent("Konec", value: endAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Autor") {
                        Text(isOwner ? "Ty" : (event.ownerName ?? "Neznámé jméno"))
                            .verifiedBadge(role: event.ownerRole)
                    }
                    if let acceptedCount = event.acceptedCount, acceptedCount > 0 {
                        LabeledContent("Jde") {
                            Label("\(acceptedCount)", systemImage: "person.2.fill")
                        }
                    }
                    if let latitude = event.latitude, let longitude = event.longitude {
                        StaticMapPreview(latitude: latitude, longitude: longitude, title: event.location ?? event.title, spanDelta: 0.002, height: 150)
                            .listRowInsets(EdgeInsets())
                        WeatherSummaryView(
                            condition: event.weatherCondition,
                            temperature: event.weatherTemperature,
                            temperatureMin: event.weatherTemperatureMin,
                            temperatureMax: event.weatherTemperatureMax,
                            isHourly: event.weatherIsHourly == 1
                        )
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
                        if isOwner || isAdmin {
                            Button("Upravit") { onEdit() }
                        }
                        if isOwner || isAdmin {
                            Button("Smazat", role: .destructive) {
                                showingDeleteConfirm = true
                            }
                        }
                        if !isOwner {
                            Button("Nahlásit akci", role: .destructive) {
                                showingReportEvent = true
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
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareURL, subject: Text(event.title)) {
                        Image(systemName: "square.and.arrow.up")
                    }
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
            .sensoryFeedback(.warning, trigger: didDelete)
            .sheet(isPresented: $showingReportEvent) {
                ReportEventView(eventId: event.id)
            }
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
            didDelete = true
            onDeleted()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se smazat akci: \(error.localizedDescription)"
            withAnimation { showingSlideToDelete = false }
        }
    }
}

#Preview {
    CalendarView()
}
