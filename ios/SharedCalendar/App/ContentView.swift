import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CalendarView()
                .tabItem { Label("Kalendář", systemImage: "calendar") }

            SwipeView()
                .tabItem { Label("Objevuj", systemImage: "rectangle.stack") }

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.circle") }
        }
    }
}

#Preview {
    ContentView()
}
