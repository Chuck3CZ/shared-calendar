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

    /// Tapping a notification (banner, lock screen, or notification center)
    /// used to just open the app to whatever screen was already showing —
    /// reported as GitHub issue #2. Routes it to the right place instead.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await DeepLinkRouter.shared.handle(pushUserInfo: response.notification.request.content.userInfo)
    }
}
