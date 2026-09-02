import SwiftUI

struct MetricsCards: View {
    let summary: VehicleSummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "Battery", value: "\(summary.batteryLevel.formatted(.number.precision(.fractionLength(0))))%", systemImage: "battery.75")
            MetricCard(title: "Range", value: "\(summary.idealRangeKm.miles.formatted(.number.precision(.fractionLength(1)))) mi", systemImage: "gauge.with.needle")
            MetricCard(title: "Odometer", value: "\(summary.odometerKm.miles.formatted(.number.precision(.fractionLength(1)))) mi", systemImage: "car.rear")
            MetricCard(title: "Last Update", value: summary.lastUpdate.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
