import SwiftUI
import Charts

struct ChargeTelemetryChartSection: View {
    let points: [ChargePoint]
    @Binding var selectedMetric: ChargeDetailView.ChargeChartMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Charging Curve")
                    .font(.headline)
                Spacer()
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(ChargeDetailView.ChargeChartMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            switch selectedMetric {
            case .power:
                ChargePowerChartView(points: points)
            case .battery:
                ChargeBatteryChartView(points: points)
            case .energy:
                ChargeEnergyChartView(points: points)
            case .currentVoltage:
                ChargeVoltageCurrentChartView(points: points)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ChargePowerChartView: View {
    let points: [ChargePoint]
    @State private var selectedDate: Date?

    private var selectedPoint: ChargePoint? {
        guard let date = selectedDate else { return nil }
        return points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let selected = selectedPoint, let p = selected.chargerPowerKW {
                    Text("\(p.formatted(.number.precision(.fractionLength(1)))) kW")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("at \(selected.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let maxP = points.compactMap(\.chargerPowerKW).max() {
                    Text("Peak Rate: \(maxP.formatted(.number.precision(.fractionLength(1)))) kW")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Press & hold to scrub")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value("Power (kW)", point.chargerPowerKW ?? 0)
                    )
                    .foregroundStyle(LinearGradient(colors: [.green.opacity(0.35), .green.opacity(0.05)], startPoint: .top, endPoint: .bottom))

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Power (kW)", point.chargerPowerKW ?? 0)
                    )
                    .foregroundStyle(.green)
                }

                if let selected = selectedPoint, let p = selected.chargerPowerKW {
                    RuleMark(x: .value("Time", selected.date))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    PointMark(
                        x: .value("Time", selected.date),
                        y: .value("Power (kW)", p)
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

struct ChargeBatteryChartView: View {
    let points: [ChargePoint]
    @State private var selectedDate: Date?

    private var selectedPoint: ChargePoint? {
        guard let date = selectedDate else { return nil }
        return points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let selected = selectedPoint, let bat = selected.batteryLevel {
                    let rangeStr = selected.idealRangeMiles.map { " (\($0.formatted(.number.precision(.fractionLength(0)))) mi)" } ?? ""
                    Text("\(Int(bat))%\(rangeStr)")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("at \(selected.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let bats = points.compactMap(\.batteryLevel)
                    if let start = bats.first, let end = bats.last {
                        Text("State of Charge: \(Int(start))% → \(Int(end))%")
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
                ForEach(points) { point in
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

struct ChargeEnergyChartView: View {
    let points: [ChargePoint]
    @State private var selectedDate: Date?

    private var selectedPoint: ChargePoint? {
        guard let date = selectedDate else { return nil }
        return points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let selected = selectedPoint, let e = selected.chargeEnergyAdded {
                    Text("\(e.formatted(.number.precision(.fractionLength(2)))) kWh")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    Text("at \(selected.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let maxEnergy = points.compactMap(\.chargeEnergyAdded).max() {
                    Text("Total Added: \(maxEnergy.formatted(.number.precision(.fractionLength(1)))) kWh")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Press & hold to scrub")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value("Energy (kWh)", point.chargeEnergyAdded ?? 0)
                    )
                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0.05)], startPoint: .top, endPoint: .bottom))

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Energy (kWh)", point.chargeEnergyAdded ?? 0)
                    )
                    .foregroundStyle(.blue)
                }

                if let selected = selectedPoint, let e = selected.chargeEnergyAdded {
                    RuleMark(x: .value("Time", selected.date))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    PointMark(
                        x: .value("Time", selected.date),
                        y: .value("Energy (kWh)", e)
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

struct ChargeVoltageCurrentChartView: View {
    let points: [ChargePoint]
    @State private var selectedDate: Date?

    private var selectedPoint: ChargePoint? {
        guard let date = selectedDate else { return nil }
        return points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let selected = selectedPoint {
                    let vStr = selected.chargerVoltage.map { "\(Int($0)) V" } ?? "-- V"
                    let aStr = selected.chargerActualCurrent.map { "\(Int($0)) A" } ?? "-- A"
                    Text("\(vStr) / \(aStr)")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("at \(selected.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if let maxV = points.compactMap(\.chargerVoltage).max() {
                        Text("Voltage: \(Int(maxV)) V")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    if let maxA = points.compactMap(\.chargerActualCurrent).max() {
                        Text("Current: \(Int(maxA)) A")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Current (A)", point.chargerActualCurrent ?? 0)
                    )
                    .foregroundStyle(.orange)

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Voltage (V)", (point.chargerVoltage ?? 0) / 10.0)
                    )
                    .foregroundStyle(.blue)
                }

                if let selected = selectedPoint {
                    RuleMark(x: .value("Time", selected.date))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    if let a = selected.chargerActualCurrent {
                        PointMark(
                            x: .value("Time", selected.date),
                            y: .value("Current (A)", a)
                        )
                        .symbol(.circle)
                        .symbolSize(60)
                        .foregroundStyle(.orange)
                    }

                    if let v = selected.chargerVoltage {
                        PointMark(
                            x: .value("Time", selected.date),
                            y: .value("Voltage (V)", v / 10.0)
                        )
                        .symbol(.circle)
                        .symbolSize(60)
                        .foregroundStyle(.blue)
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 180)
        }
    }
}
