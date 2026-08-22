import SwiftUI

struct NewEventView: View {
    @State private var title = ""
    @State private var description = ""
    @State private var location = ""
    @State private var startAt = Date()
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Akce") {
                    TextField("Název", text: $title)
                    TextField("Popis", text: $description, axis: .vertical)
                    TextField("Místo", text: $location)
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
                            Text("Vytvořit akci")
                        }
                    }
                    .disabled(title.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Nová akce")
            .alert("Akce vytvořena", isPresented: $didSubmit) {
                Button("OK") { reset() }
            }
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
                endAt: nil
            )
            _ = try await APIClient.shared.createEvent(payload)
            errorMessage = nil
            didSubmit = true
        } catch {
            errorMessage = "Nepodařilo se vytvořit akci: \(error.localizedDescription)"
        }
    }

    private func reset() {
        title = ""
        description = ""
        location = ""
        startAt = Date()
    }
}

#Preview {
    NewEventView()
}
