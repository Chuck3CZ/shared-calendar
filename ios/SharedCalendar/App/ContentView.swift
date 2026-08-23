import SwiftUI

struct ContentView: View {
    @ObservedObject private var deepLinkRouter = DeepLinkRouter.shared
    @State private var showingBugReport = false

    var body: some View {
        TabView {
            CalendarView()
                .tabItem { Label("Kalendář", systemImage: "calendar") }

            SwipeView()
                .tabItem { Label("Objevuj", systemImage: "rectangle.stack") }

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.circle") }
        }
        .sheet(item: $deepLinkRouter.pendingEvent) { event in
            EventDetailView(event: event)
        }
        .onShake { showingBugReport = true }
        .sheet(isPresented: $showingBugReport) {
            BugReportView()
        }
    }
}

#Preview {
    ContentView()
}
