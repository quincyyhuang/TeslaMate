import SwiftUI

struct DriveDetailView: View {
    let drive: DriveSummary
    @ObservedObject var viewModel: DashboardViewModel

    @State private var positions: [DrivePositionPoint] = []
    @State private var isLoadingPositions = true
    @State private var loadError: String?
    @State private var selectedMetric: DriveChartMetric = .speed

    enum DriveChartMetric: String, CaseIterable, Identifiable {
        case speed = "Speed"
        case power = "Power"
        case elevation = "Elevation"
        case battery = "Battery"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DriveSummaryCard(drive: drive, positions: positions)

                DriveMetricsGrid(drive: drive, positions: positions)

                DriveMapView(positions: positions)

                if !positions.isEmpty {
                    DriveTelemetryChartSection(positions: positions, selectedMetric: $selectedMetric)
                } else if isLoadingPositions {
                    ProgressView("Loading Telemetry...")
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding()
        }
        .navigationTitle(drive.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPositions()
        }
    }

    private func loadPositions() async {
        isLoadingPositions = true
        loadError = nil
        do {
            positions = try await viewModel.loadDrivePositions(driveID: drive.id)
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingPositions = false
    }
}

struct DriveSummaryCard: View {
    let drive: DriveSummary
    let positions: [DrivePositionPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(drive.distanceKm.miles.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    + Text(" mi")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text(drive.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label(formatDuration(minutes: drive.durationMinutes), systemImage: "clock")
                        .font(.headline)
                    if let end = drive.endDate {
                        Text("Ended \(end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if let start = drive.startAddress, !start.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.green)
                        Text(start)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
                if let end = drive.endAddress, !end.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "square.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                        Text(end)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func formatDuration(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hrs = minutes / 60
            let mins = minutes % 60
            return "\(hrs)h \(mins)m"
        }
    }
}

struct DriveMetricsGrid: View {
    let drive: DriveSummary
    let positions: [DrivePositionPoint]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let maxSpeed = drive.speedMaxKmH ?? positions.compactMap(\.speedKmH).max() {
                MetricCard(
                    title: "Max Speed",
                    value: "\(maxSpeed.miles.formatted(.number.precision(.fractionLength(0)))) mph",
                    systemImage: "speedometer"
                )
            }

            if let avgSpeed = calculateAvgSpeed() {
                MetricCard(
                    title: "Avg Speed",
                    value: "\(avgSpeed.formatted(.number.precision(.fractionLength(0)))) mph",
                    systemImage: "gauge.with.dots.needle.bottom.50percent"
                )
            }

            if let batText = batteryChangeText {
                MetricCard(
                    title: "Battery Used",
                    value: batText,
                    systemImage: "battery.50"
                )
            }

            if let rangeText = rangeUsedText {
                MetricCard(
                    title: "Rated Range Used",
                    value: rangeText,
                    systemImage: "gauge.with.needle"
                )
            }

            if let powerMax = drive.powerMaxKW ?? positions.compactMap(\.powerKW).max() {
                MetricCard(
                    title: "Peak Power",
                    value: "\(powerMax.formatted(.number.precision(.fractionLength(0)))) kW",
                    systemImage: "bolt.fill"
                )
            }

            if let powerMin = drive.powerMinKW ?? positions.compactMap(\.powerKW).min(), powerMin < 0 {
                MetricCard(
                    title: "Max Regen",
                    value: "\(powerMin.formatted(.number.precision(.fractionLength(0)))) kW",
                    systemImage: "bolt.badge.clock"
                )
            }

            if let temp = drive.outsideTempAvgC ?? positions.compactMap(\.outsideTempC).first {
                MetricCard(
                    title: "Outside Temp",
                    value: "\(temp.fahrenheit.formatted(.number.precision(.fractionLength(0))))°F",
                    systemImage: "thermometer.sun"
                )
            }

            if let insideTemp = drive.insideTempAvgC {
                MetricCard(
                    title: "Cabin Temp",
                    value: "\(insideTemp.fahrenheit.formatted(.number.precision(.fractionLength(0))))°F",
                    systemImage: "air.conditioner.horizontal"
                )
            }
        }
    }

    private func calculateAvgSpeed() -> Double? {
        guard drive.durationMinutes > 0 else { return nil }
        let miles = drive.distanceKm.miles
        let hours = Double(drive.durationMinutes) / 60.0
        return miles / hours
    }

    private var batteryChangeText: String? {
        let firstBat = positions.first?.batteryLevel
        let lastBat = positions.last?.batteryLevel
        if let start = firstBat, let end = lastBat {
            let used = start - end
            return "\(Int(start))% → \(Int(end))% (\(Int(used))%)"
        }
        return nil
    }

    private var rangeUsedText: String? {
        let startR = drive.startIdealRangeKm ?? positions.first?.idealRangeKm
        let endR = drive.endIdealRangeKm ?? positions.last?.idealRangeKm
        if let start = startR, let end = endR {
            let usedMiles = (start - end).miles
            return "\(usedMiles.formatted(.number.precision(.fractionLength(1)))) mi"
        }
        return nil
    }
}
