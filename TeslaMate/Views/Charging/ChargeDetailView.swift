import SwiftUI
import CoreLocation

struct ChargeDetailView: View {
    let charge: ChargeSummary
    @ObservedObject var viewModel: DashboardViewModel

    @State private var points: [ChargePoint] = []
    @State private var isLoadingPoints = true
    @State private var loadError: String?
    @State private var selectedMetric: ChargeChartMetric = .power

    enum ChargeChartMetric: String, CaseIterable, Identifiable {
        case power = "Power"
        case battery = "Battery"
        case energy = "Energy"
        case currentVoltage = "V / A"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ChargeSummaryCard(charge: charge, points: points)

                ChargeMetricsGrid(charge: charge, points: points)

                if let lat = charge.latitude, let lon = charge.longitude {
                    ChargeLocationMapView(
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        locationName: charge.address
                    )
                }

                if !points.isEmpty {
                    ChargeTelemetryChartSection(points: points, selectedMetric: $selectedMetric)
                } else if isLoadingPoints {
                    ProgressView("Loading Telemetry...")
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .padding()
        }
        .navigationTitle(charge.startDate.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPoints()
        }
    }

    private func loadPoints() async {
        isLoadingPoints = true
        loadError = nil
        do {
            points = try await viewModel.loadChargePoints(processID: charge.id)
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingPoints = false
    }
}

struct ChargeSummaryCard: View {
    let charge: ChargeSummary
    let points: [ChargePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(charge.energyAddedKWh.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    + Text(" kWh added")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text(charge.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label(formatDuration(minutes: charge.durationMinutes), systemImage: "clock")
                        .font(.headline)
                    if let end = charge.endDate {
                        Text("Ended \(end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let addr = charge.address, !addr.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text(addr)
                        .font(.subheadline)
                        .lineLimit(2)
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

struct ChargeMetricsGrid: View {
    let charge: ChargeSummary
    let points: [ChargePoint]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let batChange = batteryChangeText {
                MetricCard(
                    title: "Battery Level",
                    value: batChange,
                    systemImage: "battery.75"
                )
            }

            if let rangeAdded = rangeAddedText {
                MetricCard(
                    title: "Range Added",
                    value: rangeAdded,
                    systemImage: "gauge.with.needle"
                )
            }

            if let maxP = points.compactMap(\.chargerPowerKW).max() {
                MetricCard(
                    title: "Peak Power",
                    value: "\(maxP.formatted(.number.precision(.fractionLength(1)))) kW",
                    systemImage: "bolt.fill"
                )
            }

            if let cost = charge.cost {
                MetricCard(
                    title: "Cost",
                    value: "$\(cost.formatted(.number.precision(.fractionLength(2))))",
                    systemImage: "dollarsign.circle"
                )
            }

            if let used = charge.energyUsedKWh, used > 0 {
                let eff = (charge.energyAddedKWh / used) * 100.0
                MetricCard(
                    title: "Efficiency",
                    value: "\(Int(eff))%",
                    systemImage: "leaf.arrow.circlepath"
                )
            }

            if let temp = charge.outsideTempAvgC ?? points.compactMap(\.outsideTempC).first {
                MetricCard(
                    title: "Outside Temp",
                    value: "\(temp.fahrenheit.formatted(.number.precision(.fractionLength(0))))°F",
                    systemImage: "thermometer.sun"
                )
            }
        }
    }

    private var batteryChangeText: String? {
        let firstBat = charge.startBatteryLevel ?? points.first?.batteryLevel
        let lastBat = charge.endBatteryLevel ?? points.last?.batteryLevel
        if let start = firstBat, let end = lastBat {
            let diff = end - start
            return "\(Int(start))% → \(Int(end))% (\(diff >= 0 ? "+" : "")\(Int(diff))%)"
        }
        return nil
    }

    private var rangeAddedText: String? {
        let startR = charge.startIdealRangeKm ?? points.first?.idealRangeKm
        let endR = charge.endIdealRangeKm ?? points.last?.idealRangeKm
        if let start = startR, let end = endR {
            let addedMiles = (end - start).miles
            return "+\(addedMiles.formatted(.number.precision(.fractionLength(1)))) mi"
        }
        return nil
    }
}
