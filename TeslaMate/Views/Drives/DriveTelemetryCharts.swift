import SwiftUI
import Charts

struct DriveTelemetryChartSection: View {
    let positions: [DrivePositionPoint]
    @Binding var selectedMetric: DriveDetailView.DriveChartMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Telemetry Analysis")
                    .font(.headline)
                Spacer()
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(DriveDetailView.DriveChartMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            switch selectedMetric {
            case .speed:
                SpeedChartView(positions: positions)
            case .power:
                PowerChartView(positions: positions)
            case .elevation:
                ElevationChartView(positions: positions)
            case .battery:
                BatteryChartView(positions: positions)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SpeedChartView: View {
    let positions: [DrivePositionPoint]
    @State private var selectedDate: Date?

    private var selectedPoint: DrivePositionPoint? {
        guard let date = selectedDate else { return nil }
        return positions.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let selected = selectedPoint, let s = selected.speedMph {
                    Text("\(s.formatted(.number.precision(.fractionLength(0)))) mph")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    Text("at \(selected.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let maxSpeed = positions.compactMap(\.speedMph).max() {
                    Text("Max Speed: \(maxSpeed.formatted(.number.precision(.fractionLength(0)))) mph")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Press & hold to scrub")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Chart {
                ForEach(positions) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value("Speed (mph)", point.speedMph ?? 0)
                    )
                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0.05)], startPoint: .top, endPoint: .bottom))

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Speed (mph)", point.speedMph ?? 0)
                    )
                    .foregroundStyle(.blue)
                }

                if let selected = selectedPoint, let s = selected.speedMph {
                    RuleMark(x: .value("Time", selected.date))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    PointMark(
                        x: .value("Time", selected.date),
                        y: .value("Speed (mph)", s)
                    )
                    .symbol(.circle)
                    .symbolSize(70)
                    .foregroundStyle(.blue)
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 180)
        }
    }
}

struct PowerChartView: View {
    let positions: [DrivePositionPoint]
    @State private var selectedDate: Date?

    private var selectedPoint: DrivePositionPoint? {
        guard let date = selectedDate else { return nil }
        return positions.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let selected = selectedPoint, let p = selected.powerKW {
                    Text("\(p.formatted(.number.precision(.fractionLength(0)))) kW")
                        .font(.headline)
                        .foregroundStyle(p >= 0 ? .orange : .green)
                    Text("at \(selected.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let powers = positions.compactMap(\.powerKW)
                    if let maxP = powers.max(), let minP = powers.min() {
                        Text("Peak: \(maxP.formatted(.number.precision(.fractionLength(0)))) kW  •  Regen: \(minP.formatted(.number.precision(.fractionLength(0)))) kW")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Press & hold to scrub")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Chart {
                ForEach(positions) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Power (kW)", point.powerKW ?? 0)
                    )
                    .foregroundStyle((point.powerKW ?? 0) >= 0 ? .orange : .green)
                }

                if let selected = selectedPoint, let p = selected.powerKW {
                    RuleMark(x: .value("Time", selected.date))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    PointMark(
                        x: .value("Time", selected.date),
                        y: .value("Power (kW)", p)
                    )
                    .symbol(.circle)
                    .symbolSize(70)
                    .foregroundStyle(p >= 0 ? .orange : .green)
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 180)
        }
    }
}

struct ElevationChartView: View {
    let positions: [DrivePositionPoint]
    @State private var selectedDate: Date?

    private var selectedPoint: DrivePositionPoint? {
        guard let date = selectedDate else { return nil }
        return positions.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let selected = selectedPoint, let elev = selected.elevationFt {
                    Text("\(elev.formatted(.number.precision(.fractionLength(0)))) ft")
                        .font(.headline)
                        .foregroundStyle(.brown)
                    Text("at \(selected.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let elevs = positions.compactMap(\.elevationFt)
                    if let minE = elevs.min(), let maxE = elevs.max() {
                        Text("Min: \(minE.formatted(.number.precision(.fractionLength(0)))) ft  •  Max: \(maxE.formatted(.number.precision(.fractionLength(0)))) ft")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Press & hold to scrub")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Chart {
                ForEach(positions) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value("Elevation (ft)", point.elevationFt ?? 0)
                    )
                    .foregroundStyle(LinearGradient(colors: [.brown.opacity(0.35), .brown.opacity(0.05)], startPoint: .top, endPoint: .bottom))

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Elevation (ft)", point.elevationFt ?? 0)
                    )
                    .foregroundStyle(.brown)
                }

                if let selected = selectedPoint, let elev = selected.elevationFt {
                    RuleMark(x: .value("Time", selected.date))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    PointMark(
                        x: .value("Time", selected.date),
                        y: .value("Elevation (ft)", elev)
                    )
                    .symbol(.circle)
                    .symbolSize(70)
                    .foregroundStyle(.brown)
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 180)
        }
    }
}

struct BatteryChartView: View {
    let positions: [DrivePositionPoint]
    @State private var selectedDate: Date?

    private var selectedPoint: DrivePositionPoint? {
        guard let date = selectedDate else { return nil }
        return positions.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let selected = selectedPoint, let bat = selected.batteryLevel {
                    let rangeStr = selected.idealRangeKm.map { " (\(($0 * 0.621371).formatted(.number.precision(.fractionLength(0)))) mi)" } ?? ""
                    Text("\(Int(bat))%\(rangeStr)")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("at \(selected.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let bats = positions.compactMap(\.batteryLevel)
                    if let start = bats.first, let end = bats.last {
                        Text("SoC: \(Int(start))% → \(Int(end))% (\(Int(end - start))%)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Press & hold to scrub")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Chart {
                ForEach(positions) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Battery %", point.batteryLevel ?? 0)
                    )
                    .foregroundStyle(.green)
                }

                if let selected = selectedPoint, let bat = selected.batteryLevel {
                    RuleMark(x: .value("Time", selected.date))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    PointMark(
                        x: .value("Time", selected.date),
                        y: .value("Battery %", bat)
                    )
                    .symbol(.circle)
                    .symbolSize(70)
                    .foregroundStyle(.green)
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 180)
        }
    }
}
