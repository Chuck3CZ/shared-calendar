import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hexToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[push] got APNs device token: \(hexToken)")
        PushTokenStore.current = hexToken
        guard AuthManager.shared.isSignedIn else {
            print("[push] not signed in yet, deferring registration with backend")
            return
        }
        Task {
            do {
                try await APIClient.shared.registerDeviceToken(hexToken)
                print("[push] registered device token with backend")
            } catch {
                print("[push] FAILED to register device token with backend: \(error)")
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[push] FAILED to register for remote notifications: \(error)")
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Without this, a notification that arrives while the app is in the
    /// foreground is silently swallowed instead of shown.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
