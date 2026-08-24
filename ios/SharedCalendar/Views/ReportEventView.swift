import SwiftUI

/// Reachable from an event's detail screen (anyone but the owner) — flags
/// the event for an admin to review, per App Store Guideline 1.2's
/// requirement that user-generated content be reportable.
struct ReportEventView: View {
    let eventId: String

    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $reason)
                        .frame(minHeight: 100)
                } header: {
                    Text("Proč akci nahlašuješ?")
                } footer: {
                    Text("Hlášení uvidí jen administrátor.")
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
                            Text("Nahlásit")
                        }
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Nahlásit akci")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: didSubmit)
            .alert("Díky, nahlášeno", isPresented: $didSubmit) {
                Button("OK") { dismiss() }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await APIClient.shared.reportEvent(id: eventId, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
            errorMessage = nil
            didSubmit = true
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se odeslat hlášení: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ReportEventView(eventId: "preview")
}
