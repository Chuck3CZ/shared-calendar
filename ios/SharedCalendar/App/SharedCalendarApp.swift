import SwiftUI
import UIKit

@main
struct SharedCalendarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    if AuthManager.shared.isSignedIn {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
        }
    }
}
