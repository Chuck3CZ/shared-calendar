import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CalendarView()
                .tabItem { Label("Kalendář", systemImage: "calendar") }

            SwipeView()
                .tabItem { Label("Nové akce", systemImage: "rectangle.stack") }

            NewEventView()
                .tabItem { Label("Přidat", systemImage: "plus.circle") }

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.circle") }
        }
    }
}

#Preview {
    ContentView()
}
