import SwiftUI
import Charts

struct DailyDistanceChart: View {
    let points: [DailyValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Distance (Last 14 Days)")
                .font(.headline)

            if points.isEmpty {
                Text("No recent drive data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 180)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Miles", point.value)
                    )
                    .foregroundStyle(.blue.gradient)
                    .annotation(position: .top, spacing: 2) {
                        if point.value >= 0.5 {
                            Text("\(point.value.formatted(.number.precision(.fractionLength(0))))")
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
