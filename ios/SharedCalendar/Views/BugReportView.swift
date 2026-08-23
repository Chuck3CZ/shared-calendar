import SwiftUI
import UIKit

/// Presented on a shake gesture (see ShakeDetector.swift) from anywhere in
/// the app, signed in or not — a bug can happen before sign-in too.
struct BugReportView: View {
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $description)
                        .frame(minHeight: 140)
                } header: {
                    Text("Co se stalo?")
                } footer: {
                    Text("Přiloží se verze appky a typ zařízení, ať to jde dohledat.")
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
                            Text("Odeslat hlášení")
                        }
                    }
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Nahlásit bug")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: didSubmit)
            .alert("Díky, odesláno", isPresented: $didSubmit) {
                Button("OK") { dismiss() }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let device = UIDevice.current
        let payload = BugReportPayload(
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            appVersion: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            osVersion: device.systemVersion,
            deviceModel: device.model
        )
        do {
            try await APIClient.shared.submitBugReport(payload)
            errorMessage = nil
            didSubmit = true
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se odeslat hlášení: \(error.localizedDescription)"
        }
    }
}

#Preview {
    BugReportView()
}
