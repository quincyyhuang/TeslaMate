import SwiftUI
import Charts

struct DailyChargingChart: View {
    let points: [DailyValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Charging Energy (Last 14 Days)")
                .font(.headline)

            if points.isEmpty {
                Text("No recent charging data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 180)
            } else {
                Chart(points) { point in
                    AreaMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("kWh", point.value)
                    )
                    .foregroundStyle(LinearGradient(colors: [.green.opacity(0.35), .green.opacity(0.05)], startPoint: .top, endPoint: .bottom))

                    LineMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("kWh", point.value)
                    )
                    .foregroundStyle(.green)
                    .symbol(.circle)
                    .symbolSize(30)
                    .annotation(position: .top, spacing: 4) {
                        if point.value >= 0.5 {
                            Text("\(point.value.formatted(.number.precision(.fractionLength(1))))")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
