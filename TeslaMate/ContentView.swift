import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        TabView {
            DashboardTab(viewModel: viewModel)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.xyaxis.line")
                }

            DrivesTab(viewModel: viewModel)
                .tabItem {
                    Label("Drives", systemImage: "car")
                }

            ChargingTab(viewModel: viewModel)
                .tabItem {
                    Label("Charging", systemImage: "bolt.car")
                }

            SettingsTab(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .task {
            if !viewModel.isConfigured {
                showOnboarding = true
            } else {
                await viewModel.loadAll()
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(
                viewModel: viewModel,
                isPresented: $showOnboarding,
                hasCompletedOnboarding: $hasCompletedOnboarding
            )
        }
    }
}
