import SwiftUI
import UIKit

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

/// UIWindow doesn't declare `motionEnded` itself (it's inherited from
/// UIResponder), so this override in a plain extension is enough to hook
/// it — no UIWindow subclass or AppDelegate plumbing needed. UIKit calls
/// this on the window because nothing else in the responder chain claims
/// the shake motion event first.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

private struct ShakeDetector: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            action()
        }
    }
}

extension View {
    /// Runs `action` when the user shakes the device — used for the
    /// shake-to-report-a-bug gesture.
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeDetector(action: action))
    }
}
