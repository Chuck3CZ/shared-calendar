import SwiftUI

/// Small checkmark shown next to a verified user's name — wherever an
/// owner/author name is displayed (event detail, admin user list), not
/// just in the admin-only screens.
struct VerifiedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .foregroundStyle(.blue)
            .accessibilityLabel("Ověřený uživatel")
    }
}

extension View {
    /// Convenience for "only show a VerifiedBadge when this role is verified".
    @ViewBuilder
    func verifiedBadge(role: String?) -> some View {
        HStack(spacing: 4) {
            self
            if role == "verified" {
                VerifiedBadge()
            }
        }
    }
}

#Preview {
    Text("Martin").verifiedBadge(role: "verified")
}
