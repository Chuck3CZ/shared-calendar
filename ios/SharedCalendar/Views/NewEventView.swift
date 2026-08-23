import SwiftUI
import CoreLocation

struct NewEventView: View {
    var eventToEdit: Event? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var location = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var startAt = Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false
    @State private var didPopulate = false
    @State private var showingLocationPicker = false

    private var isEditing: Bool { eventToEdit != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Akce") {
                    TextField("Název", text: $title)
                    TextField("Popis", text: $description, axis: .vertical)
                    HStack {
                        TextField("Místo", text: $location)
                        Button {
                            showingLocationPicker = true
                        } label: {
                            Image(systemName: "map")
                        }
                        .buttonStyle(.borderless)
                    }
                    DatePicker("Kdy", selection: $startAt)
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
                    .disabled(title.isEmpty || isSubmitting)
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
                endAt: nil,
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
