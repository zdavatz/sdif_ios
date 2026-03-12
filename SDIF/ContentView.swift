import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BasketCheckView()
                .tabItem {
                    Label("Interaktions-Check", systemImage: "pills.circle")
                }
                .tag(0)

            ClinicalSearchView()
                .tabItem {
                    Label("Klinische Suche", systemImage: "magnifyingglass")
                }
                .tag(1)

            ATCClassView()
                .tabItem {
                    Label("ATC-Klassen", systemImage: "list.bullet.rectangle")
                }
                .tag(2)
        }
    }
}
