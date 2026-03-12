import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            BasketCheckView(showSettings: $showSettings)
                .tabItem {
                    Label("Interaktions-Check", systemImage: "pills.circle")
                }
                .tag(0)

            ClinicalSearchView(showSettings: $showSettings)
                .tabItem {
                    Label("Klinische Suche", systemImage: "magnifyingglass")
                }
                .tag(1)

            ATCClassView(showSettings: $showSettings)
                .tabItem {
                    Label("ATC-Klassen", systemImage: "list.bullet.rectangle")
                }
                .tag(2)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
