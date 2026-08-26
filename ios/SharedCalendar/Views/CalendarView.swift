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
    @ObservedObject private var repository = EventsRepository.shared
    @State private var selectedDate = Date()
    @State private var displayedMonth = Date()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingNewEvent = false
    @State private var showingNotifications = false
    @State private var editingEvent: Event?
    @State private var detailEvent: Event?
    @State private var showingSearch = false
    @State private var searchText = ""
    @State private var categoryFilter: EventCategory?
    @State private var showingCategoryFilter = false
    @AppStorage("viewAsMember") private var viewAsMember = false

    private var events: [Event] { repository.events }

    /// All the other derived lists start from this, so a category filter
    /// affects the day list, the calendar dots, and search results alike.
    private var visibleEvents: [Event] {
        guard let categoryFilter else { return events }
        return events.filter { $0.category == categoryFilter }
    }

    private var eventsForSelectedDay: [Event] {
        visibleEvents
            .filter { Calendar.current.isDate($0.startAt, inSameDayAs: selectedDate) }
            .sorted { $0.startAt < $1.startAt }
    }

    private var searchResults: [Event] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return visibleEvents
            .filter {
                $0.title.localizedCaseInsensitiveContains(needle)
                    || ($0.location?.localizedCaseInsensitiveContains(needle) ?? false)
            }
            .sorted { $0.startAt < $1.startAt }
    }

    private var eventCategoriesByDay: [DateComponents: [EventCategory]] {
        var raw: [DateComponents: Set<EventCategory>] = [:]
        for event in visibleEvents {
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: event.startAt)
            raw[comps, default: []].insert(event.category)
        }
        return raw.mapValues { categories in EventCategory.allCases.filter { categories.contains($0) } }
    }

    var body: some View {
        NavigationStack {
            // A plain ScrollView + VStack, not a List — List's iOS 26 row
            // rendering fought us on every front here: it forced filter
            // icons to a single system tint, occasionally swallowed taps on
            // buttons that shared a row with other buttons, and overrode
            // the month grid's own slide transition with its own implicit
            // one. A ScrollView also makes pull-to-refresh move the whole
            // screen as one block, calendar included, same as List did.
            ScrollView {
                VStack(spacing: 0) {
                    MonthCalendarView(selectedDate: $selectedDate, displayedMonth: $displayedMonth, eventCategoriesByDay: eventCategoriesByDay)
                        .padding(.vertical, 8)

                    Divider()

                    if !searchText.isEmpty {
                        if searchResults.isEmpty {
                            Text("Nic nenalezeno")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        } else {
                            ForEach(searchResults) { event in
                                EventRow(event: event, showDate: true) { detailEvent = event }
                                Divider()
                            }
                        }
                    } else if events.isEmpty, let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    } else if eventsForSelectedDay.isEmpty {
                        Text("Žádné akce tento den")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    } else {
                        ForEach(eventsForSelectedDay) { event in
                            EventRow(event: event, showDate: false) { detailEvent = event }
                            Divider()
                        }
                    }
                }
            }
            .navigationTitle("Kalendář")
            .searchable(text: $searchText, isPresented: $showingSearch, prompt: "Hledat akce")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Hledat akce")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingCategoryFilter = true
                    } label: {
                        Image(systemName: categoryFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(categoryFilter?.color ?? .primary)
                    }
                    .accessibilityLabel("Filtrovat podle kategorie")
                }
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
                Task { await load(forceRefresh: true) }
            }) {
                NewEventView(initialDate: selectedDate)
            }
            .sheet(isPresented: $showingNotifications) {
                NotificationHistoryView()
            }
            .sheet(isPresented: $showingCategoryFilter) {
                CategoryFilterSheet(selected: $categoryFilter)
            }
            .sheet(item: $editingEvent, onDismiss: {
                Task { await load(forceRefresh: true) }
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
                        Task { await load(forceRefresh: true) }
                    }
                )
            }
            .task { await load() }
            .refreshable { await load(forceRefresh: true) }
            .onChange(of: displayedMonth) { _, newMonth in
                Task { await load(around: newMonth) }
            }
        }
    }

    /// Reuses the cached snapshot in EventsRepository whenever it already
    /// covers this range and hasn't crossed a noon/midnight checkpoint since
    /// its last fetch — see EventsRepository for why that avoids re-hitting
    /// the server on every app open or tab switch.
    private func load(around referenceDate: Date = Date(), forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let calendar = Calendar.current
            let from = calendar.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate
            let to = calendar.date(byAdding: .month, value: 3, to: referenceDate) ?? referenceDate
            try await repository.ensureLoaded(from: from, to: to, forceRefresh: forceRefresh)
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst akce: \(error.localizedDescription)"
        }
    }
}

/// One row in the day list or in search results. `showDate` switches the
/// subtitle from just a time (day list, where the day is already implied by
/// the selected date) to a full date + time (search results, which can span
/// any day).
private struct EventRow: View {
    let event: Event
    var showDate: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: event.category.icon)
                            .foregroundStyle(event.category.color)
                        Text(event.title).font(.headline)
                    }
                    Text(showDate
                        ? event.startAt.formatted(date: .abbreviated, time: .shortened)
                        : event.startAt.formatted(date: .omitted, time: .shortened))
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
            .padding(.vertical, 10)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

/// A List used only for this short, static picker — List renders per-row
/// icon colors just fine; it's specifically the native `Menu` (backed by
/// UIMenu) that forces every item's icon to one system tint, which is why
/// the toolbar filter button used to show colorless icons.
private struct CategoryFilterSheet: View {
    @Binding var selected: EventCategory?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selected = nil
                    dismiss()
                } label: {
                    row(icon: "circle.dashed", iconColor: .secondary, title: "Vše", isSelected: selected == nil)
                }
                ForEach(EventCategory.allCases) { category in
                    Button {
                        selected = category
                        dismiss()
                    } label: {
                        row(icon: category.icon, iconColor: category.color, title: category.displayName, isSelected: selected == category)
                    }
                }
            }
            .navigationTitle("Filtrovat podle kategorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func row(icon: String, iconColor: Color, title: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // SF Symbols have wildly different intrinsic widths (three
            // people vs. a fork) — centering each icon in its own fixed
            // 28×28 slot, instead of just giving the Image a width, is what
            // actually keeps every row's icon and text starting at the
            // same x regardless of which symbol it is.
            ZStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
            }
            .frame(width: 28, height: 28)
            Text(title)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(.blue)
            }
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
    }
}

/// A custom month grid, replacing SwiftUI's `DatePicker(.graphical)`
/// (backed by UIKit's `UICalendarView`). That system component can't show
/// per-day decorations and has its own layout bugs — it resizes its cell
/// grid to however many weeks a month needs (4 vs 6), and in landscape that
/// internal resizing can leave the grid shifted and cell spacing uneven
/// between adjacent months. Always laying out a fixed 6-week (42-day) grid
/// here avoids both.
private struct MonthCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let eventCategoriesByDay: [DateComponents: [EventCategory]]

    // Which edge the incoming month slides in from — set right before
    // displayedMonth changes so the whole grid pages like a deck of cards,
    // instead of every cell individually cross-fading its number in place.
    @State private var incomingEdge: Edge = .trailing
    @State private var showingDatePicker = false
    @State private var pickerDate = Date()

    private let calendar = Calendar.current

    private var days: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek.start) }
    }

    private var weekdaySymbols: [String] {
        var czechCalendar = calendar
        czechCalendar.locale = Locale(identifier: "cs_CZ")
        let symbols = czechCalendar.veryShortWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1
        return Array(symbols[firstWeekdayIndex...] + symbols[..<firstWeekdayIndex])
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: displayedMonth).capitalized(with: Locale(identifier: "cs_CZ"))
    }

    private func categories(on date: Date) -> [EventCategory] {
        eventCategoriesByDay[calendar.dateComponents([.year, .month, .day], from: date)] ?? []
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    pickerDate = displayedMonth
                    showingDatePicker = true
                } label: {
                    Text(monthTitle)
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .id(displayedMonth)
                .transition(.asymmetric(
                    insertion: .move(edge: incomingEdge),
                    removal: .move(edge: incomingEdge == .trailing ? .leading : .trailing)
                ))
                .frame(maxWidth: .infinity)
                .clipped()
                Spacer()
                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { date in
                    dayCell(for: date)
                }
            }
            .id(displayedMonth)
            .transition(.asymmetric(
                insertion: .move(edge: incomingEdge),
                removal: .move(edge: incomingEdge == .trailing ? .leading : .trailing)
            ))
            .clipped()
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    changeMonth(by: value.translation.width < 0 ? 1 : -1)
                }
        )
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("Datum", selection: $pickerDate, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()
                    .navigationTitle("Přejít na datum")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Zrušit") { showingDatePicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Přejít") {
                                jump(to: pickerDate)
                                showingDatePicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.height(320)])
        }
    }

    private func jump(to date: Date) {
        selectedDate = date
        incomingEdge = date > displayedMonth ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.25)) {
            displayedMonth = date
        }
    }

    // Days outside the displayed month used to show as dimmed numbers, the
    // same way UIKit's own calendar does it — but with a fixed 42-cell grid
    // that's always at least a week of them, and testing showed people read
    // the dim numbers as "this month, just faded" rather than "not this
    // month", so those cells now render blank instead (still occupying
    // their grid slot, just with nothing tappable in it).
    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        if calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
            let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
            let isToday = calendar.isDateInToday(date)

            Button {
                selectedDate = date
            } label: {
                VStack(spacing: 4) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.body)
                        .fontWeight(isToday ? .bold : .regular)
                        .frame(width: 32, height: 32)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background {
                            if isSelected {
                                Circle().fill(Color.accentColor)
                            } else if isToday {
                                Circle().stroke(Color.accentColor, lineWidth: 1)
                            }
                        }

                    HStack(spacing: 3) {
                        ForEach(categories(on: date).prefix(3)) { category in
                            Circle().fill(category.color).frame(width: 5, height: 5)
                        }
                    }
                    .frame(height: 5)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 4) {
                Color.clear.frame(width: 32, height: 32)
                Color.clear.frame(height: 5)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func changeMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        incomingEdge = value > 0 ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.25)) {
            displayedMonth = newMonth
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
    @State private var showingInteractiveMap = false
    @State private var didDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var reminderMinutes: [Int] = []
    @State private var showingReportEvent = false
    @AppStorage("viewAsMember") private var viewAsMember = false

    private var isOwner: Bool { auth.session?.profile.id == event.ownerId }
    private var isAdmin: Bool { auth.session?.profile.role == "admin" && !viewAsMember }
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
                Section {
                    LabeledContent("Název") { CopyableValue(text: event.title, bold: true) }
                    LabeledContent("Kategorie") {
                        HStack(spacing: 6) {
                            Image(systemName: event.category.icon)
                                .foregroundStyle(event.category.color)
                            Text(event.category.displayName)
                        }
                    }
                    if let description = event.description, !description.isEmpty {
                        LabeledContent("Popis", value: description)
                    }
                    LabeledContent("Kdy", value: event.startAt.formatted(date: .abbreviated, time: .shortened))
                    if let endAt = event.endAt {
                        LabeledContent("Konec", value: endAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let acceptedCount = event.acceptedCount, acceptedCount > 0 {
                        LabeledContent("Zúčastní se") {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                Text("\(acceptedCount)")
                            }
                        }
                    }
                    if let location = event.location, !location.isEmpty {
                        LabeledContent("Místo") { CopyableValue(text: location) }
                    }
                    if let latitude = event.latitude, let longitude = event.longitude {
                        Button {
                            showingInteractiveMap = true
                        } label: {
                            StaticMapPreview(latitude: latitude, longitude: longitude, title: event.location ?? event.title, spanDelta: 0.002, height: 150)
                        }
                        .buttonStyle(.plain)
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
                } header: {
                    HStack {
                        Text("Akci vytvořil:")
                        Spacer()
                        Text(isOwner ? "Ty" : (event.ownerName ?? "Neznámé jméno"))
                            .verifiedBadge(role: event.ownerRole)
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
            .sheet(isPresented: $showingInteractiveMap) {
                if let latitude = event.latitude, let longitude = event.longitude {
                    InteractiveMapView(latitude: latitude, longitude: longitude, title: event.location ?? event.title)
                }
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
