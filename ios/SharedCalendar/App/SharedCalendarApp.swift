import SwiftUI
import UIKit

@main
struct SharedCalendarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    guard AuthManager.shared.isSignedIn else { return }
                    Task { await AuthManager.shared.registerForPushNotifications() }
                }
        }
    }
}
