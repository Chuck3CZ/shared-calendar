import SwiftUI
import CoreLocation

struct NewEventView: View {
    var eventToEdit: Event? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var location = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var startAt: Date
    @State private var hasEndTime = false
    @State private var endAt = Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false
    @State private var didPopulate = false
    @State private var showingLocationPicker = false

    private var isEditing: Bool { eventToEdit != nil }

    /// `initialDate` is the day currently selected in the calendar (if any)
    /// — used only when creating a new event, so "Kdy" opens already on the
    /// day the user was looking at instead of always defaulting to today.
    /// Keeps the current time-of-day, just swaps in that day.
    init(eventToEdit: Event? = nil, initialDate: Date? = nil) {
        self.eventToEdit = eventToEdit
        if let initialDate {
            let calendar = Calendar.current
            let now = Date()
            let combined = calendar.date(
                bySettingHour: calendar.component(.hour, from: now),
                minute: calendar.component(.minute, from: now),
                second: 0,
                of: initialDate
            )
            _startAt = State(initialValue: combined ?? initialDate)
        } else {
            _startAt = State(initialValue: Date())
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Název", text: $title)
                    TextField("Popis", text: $description, axis: .vertical)
                    Button {
                        showingLocationPicker = true
                    } label: {
                        HStack {
                            Text("Místo")
                                .foregroundStyle(location.isEmpty ? .primary : .secondary)
                            Spacer()
                            Text(location.isEmpty ? "Vybrat na mapě" : location)
                                .foregroundStyle(location.isEmpty ? .secondary : .primary)
                                .multilineTextAlignment(.trailing)
                            Image(systemName: "map")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !location.isEmpty {
                        Button("Odebrat místo", role: .destructive) {
                            location = ""
                            coordinate = nil
                        }
                    }
                    DatePicker("Kdy", selection: $startAt)
                        .onChange(of: startAt) { _, newValue in
                            if hasEndTime && endAt <= newValue {
                                endAt = newValue.addingTimeInterval(3600)
                            }
                        }
                    Toggle("Konec akce", isOn: $hasEndTime.animation())
                        .onChange(of: hasEndTime) { _, newValue in
                            if newValue && endAt <= startAt {
                                endAt = startAt.addingTimeInterval(3600)
                            }
                        }
                    if hasEndTime {
                        DatePicker("Konec", selection: $endAt, in: startAt...)
                    }
                } header: {
                    Text("Akce")
                } footer: {
                    Text("Místo je povinné.")
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(isEditing ? "Uložit změny" : "Vytvořit akci")
                        }
                    }
                    .disabled(title.isEmpty || location.isEmpty || isSubmitting)
                }
            }
            .navigationTitle(isEditing ? "Upravit akci" : "Nová akce")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
            }
            .onAppear { populateIfNeeded() }
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerView(initialAddress: location, initialCoordinate: coordinate) { address, newCoordinate in
                    location = address
                    coordinate = newCoordinate
                }
            }
            .alert(isEditing ? "Akce upravena" : "Akce vytvořena", isPresented: $didSubmit) {
                Button("OK") { dismiss() }
            }
            .sensoryFeedback(.success, trigger: didSubmit)
            .sensoryFeedback(trigger: errorMessage) { _, new in new != nil ? .error : nil }
        }
    }

    private func populateIfNeeded() {
        guard !didPopulate, let event = eventToEdit else { return }
        didPopulate = true
        title = event.title
        description = event.description ?? ""
        location = event.location ?? ""
        if let lat = event.latitude, let lng = event.longitude {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        startAt = event.startAt
        if let existingEndAt = event.endAt {
            hasEndTime = true
            endAt = existingEndAt
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let formatter = ISO8601DateFormatter()
            let payload = NewEventPayload(
                title: title,
                description: description.isEmpty ? nil : description,
                location: location.isEmpty ? nil : location,
                startAt: formatter.string(from: startAt),
                endAt: hasEndTime ? formatter.string(from: endAt) : nil,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude
            )
            if let event = eventToEdit {
                _ = try await APIClient.shared.updateEvent(id: event.id, payload)
            } else {
                _ = try await APIClient.shared.createEvent(payload)
            }
            errorMessage = nil
            didSubmit = true
        } catch {
            guard !error.isCancellation else { return }
            if case APIError.server(let message) = error {
                errorMessage = message
            } else {
                errorMessage = "Nepodařilo se uložit akci: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NewEventView()
}
