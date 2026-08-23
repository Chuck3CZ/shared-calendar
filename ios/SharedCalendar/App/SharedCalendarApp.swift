import SwiftUI
import UIKit

@main
struct SharedCalendarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    guard AuthManager.shared.isSignedIn else { return }
                    Task {
                        await AuthManager.shared.registerForPushNotifications()
                        await AuthManager.shared.refreshBadge()
                    }
                }
                .onOpenURL { url in
                    DeepLinkRouter.shared.handle(url: url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await AuthManager.shared.refreshBadge() }
        }
    }
}
