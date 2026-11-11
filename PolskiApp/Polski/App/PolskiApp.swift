import SwiftUI

@main
struct PolskiApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.brand)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if !store.state.onboarded {
                OnboardingView()
            } else if !store.state.placementDone {
                PlacementFlowView(isRetake: false)
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut, value: store.state.onboarded)
        .animation(.easeInOut, value: store.state.placementDone)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Lernen", systemImage: "book.fill") }
            StatsView()
                .tabItem { Label("Fortschritt", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
    }
}
