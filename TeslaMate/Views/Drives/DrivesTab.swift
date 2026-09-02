import SwiftUI

struct DrivesTab: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TimeFilterHeaderView(selectedFilter: $viewModel.drivesDateFilter) {
                    Task { await viewModel.loadDrivesOnly() }
                }

                Divider()
                    .padding(.top, 4)

                Group {
                    if viewModel.recentDrives.isEmpty && viewModel.isLoading {
                        ProgressView("Loading Drives...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.recentDrives.isEmpty {
                        ContentUnavailableView(
                            "No Drives Found",
                            systemImage: "car",
                            description: Text(viewModel.drivesDateFilter == .all ? "Recent drives will appear here once recorded by TeslaMate." : "No drives recorded for the selected time range.")
                        )
                    } else {
                        List {
                            ForEach(viewModel.recentDrives) { drive in
                                NavigationLink {
                                    DriveDetailView(drive: drive, viewModel: viewModel)
                                } label: {
                                    DriveRow(drive: drive)
                                }
                                .task {
                                    await viewModel.loadMoreDrivesIfNeeded(currentItem: drive)
                                }
                            }

                            if viewModel.isLoadingMoreDrives {
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
                            await viewModel.loadDrivesOnly()
                        }
                    }
                }
            }
            .navigationTitle("Drives")
        }
    }
}

struct DriveRow: View {
    let drive: DriveSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(drive.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Spacer()
                Text("\(drive.distanceKm.miles.formatted(.number.precision(.fractionLength(1)))) mi")
                    .font(.headline)
                    .foregroundStyle(.blue)
            }

            HStack {
                Text(formatDuration(minutes: drive.durationMinutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let maxSpeed = drive.speedMaxKmH {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("Max: \(maxSpeed.miles.formatted(.number.precision(.fractionLength(0)))) mph")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let start = drive.startAddress, let end = drive.endAddress, !start.isEmpty || !end.isEmpty {
                Text("\(start.isEmpty ? "Unknown" : start) → \(end.isEmpty ? "Unknown" : end)")
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
