import Foundation

/// Sign-in success immediately swaps SignInPromptView out for the signed-in
/// content, so a debug caption shown only there would flash and vanish
/// before it could be read. This keeps the last capture around so Profile
/// can also show it — temporary, remove once the missing-name issue is understood.
enum SignInDebugLog {
    static var lastAppleNameCapture: String?
}
