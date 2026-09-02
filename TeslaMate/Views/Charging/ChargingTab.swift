import SwiftUI

struct ChargingTab: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TimeFilterHeaderView(selectedFilter: $viewModel.chargingDateFilter) {
                    Task { await viewModel.loadChargingOnly() }
                }

                Divider()
                    .padding(.top, 4)

                Group {
                    if viewModel.recentCharges.isEmpty && viewModel.isLoading {
                        ProgressView("Loading Charges...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.recentCharges.isEmpty {
                        ContentUnavailableView(
                            "No Charging Sessions Found",
                            systemImage: "bolt.car",
                            description: Text(viewModel.chargingDateFilter == .all ? "Recent charging sessions will appear here once recorded by TeslaMate." : "No charging sessions recorded for the selected time range.")
                        )
                    } else {
                        List {
                            ForEach(viewModel.recentCharges) { charge in
                                NavigationLink {
                                    ChargeDetailView(charge: charge, viewModel: viewModel)
                                } label: {
                                    ChargeRow(charge: charge)
                                }
                                .task {
                                    await viewModel.loadMoreChargesIfNeeded(currentItem: charge)
                                }
                            }

                            if viewModel.isLoadingMoreCharges {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .refreshable {
                            await viewModel.loadChargingOnly()
                        }
                    }
                }
            }
            .navigationTitle("Charging")
        }
    }
}

struct ChargeRow: View {
    let charge: ChargeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(charge.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Spacer()
                Text("+\(charge.energyAddedKWh.formatted(.number.precision(.fractionLength(1)))) kWh")
                    .font(.headline)
                    .foregroundStyle(.green)
            }

            HStack {
                Text(formatDuration(minutes: charge.durationMinutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let startBat = charge.startBatteryLevel, let endBat = charge.endBatteryLevel {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(Int(startBat))% → \(Int(endBat))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let cost = charge.cost {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("$\(cost.formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let addr = charge.address, !addr.isEmpty {
                Text(addr)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
    }
}
