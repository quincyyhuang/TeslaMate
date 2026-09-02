import SwiftUI

struct DashboardTab: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showSetupSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.isConfigured {
                    ContentUnavailableView {
                        Label("Configure Grafana", systemImage: "gearshape")
                    } description: {
                        Text("Connect your Grafana instance to view live telemetry, drive analytics, and charging curves.")
                    } actions: {
                        Button {
                            showSetupSheet = true
                        } label: {
                            Text("Start Setup Guide")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .sheet(isPresented: $showSetupSheet) {
                        OnboardingView(
                            viewModel: viewModel,
                            isPresented: $showSetupSheet,
                            hasCompletedOnboarding: .constant(true)
                        )
                    }
                } else if !viewModel.hasDashboardData && viewModel.isLoading {
                    ProgressView("Loading TeslaMate Data...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.hasDashboardData && viewModel.errorMessage != nil {
                    ContentUnavailableView(
                        "Could not load data",
                        systemImage: "wifi.exclamationmark",
                        description: Text(viewModel.errorMessage ?? "")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let error = viewModel.errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                    Text(error)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            }

                            MetricsCards(summary: viewModel.summary)

                            DailyDistanceChart(points: viewModel.driveDistanceDaily)

                            DailyChargingChart(points: viewModel.chargingEnergyDaily)
                        }
                        .padding()
                    }
                    .refreshable {
                        await viewModel.loadAll()
                    }
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await viewModel.loadAll() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }
}
