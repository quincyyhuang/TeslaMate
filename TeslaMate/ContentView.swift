import SwiftUI
import Charts
import Combine
import MapKit

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        TabView {
            DashboardTab(viewModel: viewModel)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.xyaxis.line")
                }

            DrivesTab(viewModel: viewModel)
                .tabItem {
                    Label("Drives", systemImage: "car")
                }

            ChargingTab(viewModel: viewModel)
                .tabItem {
                    Label("Charging", systemImage: "bolt.car")
                }

            SettingsTab(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .task {
            await viewModel.loadAll()
        }
    }
}

private struct DashboardTab: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.isConfigured {
                    ContentUnavailableView(
                        "Configure Grafana",
                        systemImage: "gearshape",
                        description: Text("Add Grafana URL, API token, datasource UID, and car ID in Settings.")
                    )
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
                                        .foregroundStyle(.orange)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            }

                            MetricsCards(summary: viewModel.summary)

                            if !viewModel.driveDistanceDaily.isEmpty {
                                DailyDistanceChart(points: viewModel.driveDistanceDaily)
                            }

                            if !viewModel.chargingEnergyDaily.isEmpty {
                                DailyChargingChart(points: viewModel.chargingEnergyDaily)
                            }
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

private struct DrivesTab: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.recentDrives.isEmpty && viewModel.isLoading {
                    ProgressView("Loading Drives...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.recentDrives.isEmpty && viewModel.errorMessage != nil {
                    ContentUnavailableView(
                        "Could not load drives",
                        systemImage: "car.side.lock",
                        description: Text(viewModel.errorMessage ?? "")
                    )
                } else {
                    List {
                        ForEach(viewModel.recentDrives) { drive in
                            NavigationLink(value: drive) {
                                DriveRowView(drive: drive)
                            }
                            .onAppear {
                                Task { await viewModel.loadMoreDrivesIfNeeded(currentItem: drive) }
                            }
                        }

                        if viewModel.isLoadingMoreDrives {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: DriveSummary.self) { drive in
                DriveDetailView(drive: drive, viewModel: viewModel)
            }
            .refreshable {
                await viewModel.loadDrivesOnly()
            }
            .navigationTitle("Drives")
        }
    }
}

private struct DriveRowView: View {
    let drive: DriveSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(drive.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Spacer()
                Text("\(drive.distanceKm.miles.formatted(.number.precision(.fractionLength(1)))) mi")
                    .font(.headline)
                    .foregroundStyle(.tint)
            }

            if let route = routeTitle, !route.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(route)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 12) {
                Label("\(drive.durationMinutes) min", systemImage: "clock")
                if let speedMax = drive.speedMaxKmH {
                    Label("Max: \(speedMax.miles.formatted(.number.precision(.fractionLength(0)))) mph", systemImage: "speedometer")
                }
                if let temp = drive.outsideTempAvgC {
                    Label("\(temp.fahrenheit.formatted(.number.precision(.fractionLength(0))))°F", systemImage: "thermometer.medium")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var routeTitle: String? {
        if let start = drive.startAddress, let end = drive.endAddress, start != end {
            return "\(start) → \(end)"
        } else if let address = drive.startAddress ?? drive.endAddress {
            return address
        }
        return nil
    }
}

private struct DriveDetailView: View {
    let drive: DriveSummary
    @ObservedObject var viewModel: DashboardViewModel

    @State private var positions: [DrivePositionPoint] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedChartMetric = ChartMetric.speed

    enum ChartMetric: String, CaseIterable, Identifiable {
        case speed = "Speed"
        case power = "Power"
        case elevation = "Elevation"
        case battery = "Battery"

        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .speed: return "speedometer"
            case .power: return "bolt.fill"
            case .elevation: return "mountain.2.fill"
            case .battery: return "battery.75"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Route & Map View
                DriveMapView(coordinates: positions.map(\.coordinate))

                // Location Summary Card
                DriveRouteHeaderCard(drive: drive, positions: positions)

                // Quick Metric Cards Grid
                DriveMetricsGrid(drive: drive, positions: positions)

                // Interactive Telemetry Chart
                if !positions.isEmpty {
                    DriveTelemetryChartSection(
                        positions: positions,
                        selectedMetric: $selectedChartMetric
                    )
                } else if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading route telemetry...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                } else if let error = errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text("Could not load telemetry")
                            .font(.headline)
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadPositions() }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle(drive.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPositions()
        }
        .refreshable {
            await loadPositions()
        }
    }

    private func loadPositions() async {
        isLoading = true
        errorMessage = nil
        do {
            positions = try await viewModel.loadDrivePositions(driveID: drive.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct DriveMapView: View {
    let coordinates: [CLLocationCoordinate2D]

    @State private var position: MapCameraPosition = .automatic
    @State private var isFullScreen = false
    @State private var mapStyle = MapStyleChoice.standard

    enum MapStyleChoice: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case hybrid = "Satellite"

        var id: String { rawValue }
        var style: MapStyle {
            switch self {
            case .standard: return .standard(elevation: .realistic)
            case .hybrid: return .hybrid(elevation: .realistic)
            }
        }
    }

    var body: some View {
        Group {
            if coordinates.isEmpty {
                ContentUnavailableView("No GPS Route Data", systemImage: "map")
                    .frame(height: 240)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ZStack(alignment: .topTrailing) {
                    Map(position: $position, interactionModes: .all) {
                        if coordinates.count > 1 {
                            MapPolyline(coordinates: coordinates)
                                .stroke(Color.blue, lineWidth: 4)
                        }

                        if let start = coordinates.first {
                            Marker("Start", coordinate: start)
                                .tint(.green)
                        }

                        if let end = coordinates.last, coordinates.count > 1 {
                            Marker("End", coordinate: end)
                                .tint(.red)
                        }
                    }
                    .mapStyle(mapStyle.style)
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 8) {
                        Button {
                            withAnimation {
                                position = .automatic
                            }
                        } label: {
                            Image(systemName: "location.viewfinder")
                                .font(.system(size: 13, weight: .bold))
                                .padding(8)
                                .background(.thinMaterial, in: Circle())
                        }

                        Button {
                            isFullScreen = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 13, weight: .bold))
                                .padding(8)
                                .background(.thinMaterial, in: Circle())
                        }
                    }
                    .padding(10)
                }
                .sheet(isPresented: $isFullScreen) {
                    FullScreenMapView(coordinates: coordinates, mapStyle: $mapStyle)
                }
            }
        }
    }
}

private struct FullScreenMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    @Binding var mapStyle: DriveMapView.MapStyleChoice
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(position: $position, interactionModes: .all) {
                    if coordinates.count > 1 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(Color.blue, lineWidth: 5)
                    }

                    if let start = coordinates.first {
                        Marker("Start", coordinate: start)
                            .tint(.green)
                    }

                    if let end = coordinates.last, coordinates.count > 1 {
                        Marker("End", coordinate: end)
                            .tint(.red)
                    }
                }
                .mapStyle(mapStyle.style)
                .mapControls {
                    MapCompass()
                    MapPitchToggle()
                    MapScaleView()
                }

                VStack(alignment: .trailing, spacing: 12) {
                    Picker("Style", selection: $mapStyle) {
                        ForEach(DriveMapView.MapStyleChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

                    Button {
                        withAnimation {
                            position = .automatic
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.viewfinder")
                            Text("Fit Route")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                    }
                }
                .padding()
            }
            .navigationTitle("Drive Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct DriveRouteHeaderCard: View {
    let drive: DriveSummary
    let positions: [DrivePositionPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trip Overview")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(drive.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                }
                Spacer()
                if let end = drive.endDate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Ended")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(end.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start Location")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(drive.startAddress ?? "Unknown Departure Point")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Destination")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(drive.endAddress ?? "Unknown Arrival Point")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DriveMetricsGrid: View {
    let drive: DriveSummary
    let positions: [DrivePositionPoint]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                title: "Distance",
                value: "\(drive.distanceKm.miles.formatted(.number.precision(.fractionLength(1)))) mi",
                systemImage: "map"
            )

            MetricCard(
                title: "Duration",
                value: formatDuration(minutes: drive.durationMinutes),
                systemImage: "clock"
            )

            MetricCard(
                title: "Avg Speed",
                value: "\(averageSpeedMph.formatted(.number.precision(.fractionLength(1)))) mph",
                systemImage: "speedometer"
            )

            if let maxSpeed = drive.speedMaxKmH ?? positions.compactMap(\.speedKmH).max() {
                MetricCard(
                    title: "Max Speed",
                    value: "\(maxSpeed.miles.formatted(.number.precision(.fractionLength(0)))) mph",
                    systemImage: "gauge.with.dots.needle.67percent"
                )
            }

            if let batteryChange = batteryChangeText {
                MetricCard(
                    title: "Battery Used",
                    value: batteryChange,
                    systemImage: "battery.75"
                )
            }

            if let rangeEfficiency = rangeEfficiencyText {
                MetricCard(
                    title: "Range Used",
                    value: rangeEfficiency,
                    systemImage: "gauge.with.needle"
                )
            }

            if let powerMax = drive.powerMaxKW ?? positions.compactMap(\.powerKW).max() {
                MetricCard(
                    title: "Max Power",
                    value: "\(powerMax.formatted(.number.precision(.fractionLength(0)))) kW",
                    systemImage: "bolt.fill"
                )
            }

            if let powerMin = drive.powerMinKW ?? positions.compactMap(\.powerKW).min() {
                MetricCard(
                    title: "Max Regen",
                    value: "\(abs(powerMin).formatted(.number.precision(.fractionLength(0)))) kW",
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
                    title: "Inside Temp",
                    value: "\(insideTemp.fahrenheit.formatted(.number.precision(.fractionLength(0))))°F",
                    systemImage: "thermometer.medium"
                )
            }
        }
    }

    private var averageSpeedMph: Double {
        guard drive.durationMinutes > 0 else { return 0 }
        let distanceMiles = drive.distanceKm.miles
        let hours = Double(drive.durationMinutes) / 60.0
        return distanceMiles / hours
    }

    private var batteryChangeText: String? {
        let firstBat = positions.first?.batteryLevel
        let lastBat = positions.last?.batteryLevel
        if let start = firstBat, let end = lastBat {
            let diff = end - start
            return "\(Int(start))% → \(Int(end))% (\(diff >= 0 ? "+" : "")\(Int(diff))%)"
        }
        return nil
    }

    private var rangeEfficiencyText: String? {
        let startR = drive.startIdealRangeKm ?? positions.first?.idealRangeKm
        let endR = drive.endIdealRangeKm ?? positions.last?.idealRangeKm
        if let start = startR, let end = endR {
            let usedMiles = (start - end).miles
            return "-\(usedMiles.formatted(.number.precision(.fractionLength(1)))) mi"
        }
        return nil
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

private struct DriveTelemetryChartSection: View {
    let positions: [DrivePositionPoint]
    @Binding var selectedMetric: DriveDetailView.ChartMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Telemetry Analysis")
                    .font(.headline)
                Spacer()
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(DriveDetailView.ChartMetric.allCases) { metric in
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

private struct SpeedChartView: View {
    let positions: [DrivePositionPoint]
    @State private var selectedDate: Date?

    private var selectedPoint: DrivePositionPoint? {
        guard let date = selectedDate else { return nil }
        return positions.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let selected = selectedPoint, let speed = selected.speedMph {
                    Text("\(speed.formatted(.number.precision(.fractionLength(1)))) mph")
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

                if let selected = selectedPoint, let speed = selected.speedMph {
                    RuleMark(x: .value("Time", selected.date))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    PointMark(
                        x: .value("Time", selected.date),
                        y: .value("Speed (mph)", speed)
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

private struct PowerChartView: View {
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
                    let isRegen = p < 0
                    Text("\(isRegen ? "" : "+")\(p.formatted(.number.precision(.fractionLength(1)))) kW (\(isRegen ? "Regen" : "Power"))")
                        .font(.headline)
                        .foregroundStyle(isRegen ? .green : .orange)
                    Text("at \(selected.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    if let maxPower = positions.compactMap(\.powerKW).max() {
                        Text("Peak: +\(maxPower.formatted(.number.precision(.fractionLength(0)))) kW")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if let minPower = positions.compactMap(\.powerKW).min() {
                        Text("Regen: \(minPower.formatted(.number.precision(.fractionLength(0)))) kW")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Chart {
                ForEach(positions) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Power (kW)", point.powerKW ?? 0)
                    )
                    .foregroundStyle((point.powerKW ?? 0) >= 0 ? Color.orange : Color.green)
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
                    .foregroundStyle(p >= 0 ? Color.orange : Color.green)
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 180)
        }
    }
}

private struct ElevationChartView: View {
    let positions: [DrivePositionPoint]
    @State private var selectedDate: Date?

    private var selectedPoint: DrivePositionPoint? {
        guard let date = selectedDate else { return nil }
        return positions.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let selected = selectedPoint, let elevation = selected.elevationFt {
                    Text("\(elevation.formatted(.number.precision(.fractionLength(0)))) ft")
                        .font(.headline)
                        .foregroundStyle(.purple)
                    Text("at \(selected.date.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let elevations = positions.compactMap(\.elevationFt)
                    if let minE = elevations.min(), let maxE = elevations.max() {
                        Text("Elevation: \(minE.formatted(.number.precision(.fractionLength(0)))) ft – \(maxE.formatted(.number.precision(.fractionLength(0)))) ft")
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
                    .foregroundStyle(LinearGradient(colors: [.purple.opacity(0.35), .purple.opacity(0.05)], startPoint: .top, endPoint: .bottom))

                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Elevation (ft)", point.elevationFt ?? 0)
                    )
                    .foregroundStyle(.purple)
                }

                if let selected = selectedPoint, let elevation = selected.elevationFt {
                    RuleMark(x: .value("Time", selected.date))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                    PointMark(
                        x: .value("Time", selected.date),
                        y: .value("Elevation (ft)", elevation)
                    )
                    .symbol(.circle)
                    .symbolSize(70)
                    .foregroundStyle(.purple)
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 180)
        }
    }
}

private struct BatteryChartView: View {
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

private struct ChargingTab: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.recentCharges.isEmpty && viewModel.isLoading {
                    ProgressView("Loading Charging...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.recentCharges.isEmpty && viewModel.errorMessage != nil {
                    ContentUnavailableView(
                        "Could not load charging",
                        systemImage: "bolt.slash",
                        description: Text(viewModel.errorMessage ?? "")
                    )
                } else {
                    List {
                        ForEach(viewModel.recentCharges) { charge in
                            NavigationLink(value: charge) {
                                ChargeRowView(charge: charge)
                            }
                            .onAppear {
                                Task { await viewModel.loadMoreChargesIfNeeded(currentItem: charge) }
                            }
                        }

                        if viewModel.isLoadingMoreCharges {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: ChargeSummary.self) { charge in
                ChargeDetailView(charge: charge, viewModel: viewModel)
            }
            .refreshable {
                await viewModel.loadChargingOnly()
            }
            .navigationTitle("Charging")
        }
    }
}

private struct ChargeRowView: View {
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

            if let address = charge.address, !address.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 12) {
                Label("\(charge.durationMinutes) min", systemImage: "clock")

                if let start = charge.startBatteryLevel, let end = charge.endBatteryLevel {
                    Label("\(Int(start))% → \(Int(end))%", systemImage: "battery.75")
                }

                if let cost = charge.cost, cost > 0 {
                    Label("$\(cost.formatted(.number.precision(.fractionLength(2))))", systemImage: "dollarsign")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ChargeDetailView: View {
    let charge: ChargeSummary
    @ObservedObject var viewModel: DashboardViewModel

    @State private var chargePoints: [ChargePoint] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedChartMetric = ChargeChartMetric.power

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
                // Location Map (if coordinates exist)
                if let lat = charge.latitude, let lon = charge.longitude {
                    ChargeLocationMapView(
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        title: charge.address ?? "Charging Station"
                    )
                }

                // Location & Overview Card
                ChargeHeaderCard(charge: charge)

                // Metric Cards Grid
                ChargeMetricsGrid(charge: charge, points: chargePoints)

                // Telemetry Analysis Chart Section
                if !chargePoints.isEmpty {
                    ChargeTelemetryChartSection(
                        points: chargePoints,
                        selectedMetric: $selectedChartMetric
                    )
                } else if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading charging telemetry...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                } else if let error = errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text("Could not load telemetry")
                            .font(.headline)
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadPoints() }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle(charge.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPoints()
        }
        .refreshable {
            await loadPoints()
        }
    }

    private func loadPoints() async {
        isLoading = true
        errorMessage = nil
        do {
            chargePoints = try await viewModel.loadChargePoints(processID: charge.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct ChargeLocationMapView: View {
    let coordinate: CLLocationCoordinate2D
    let title: String

    @State private var position: MapCameraPosition
    @State private var isFullScreen = false

    init(coordinate: CLLocationCoordinate2D, title: String) {
        self.coordinate = coordinate
        self.title = title
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 3500,
            longitudinalMeters: 3500
        )
        _position = State(initialValue: .region(region))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position, interactionModes: .all) {
                Marker(title, coordinate: coordinate)
                    .tint(.green)
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    withAnimation {
                        let region = MKCoordinateRegion(
                            center: coordinate,
                            latitudinalMeters: 3500,
                            longitudinalMeters: 3500
                        )
                        position = .region(region)
                    }
                } label: {
                    Image(systemName: "location.viewfinder")
                        .font(.system(size: 13, weight: .bold))
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                }

                Button {
                    isFullScreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                }
            }
            .padding(10)
        }
        .sheet(isPresented: $isFullScreen) {
            FullScreenChargeMapView(coordinate: coordinate, title: title)
        }
    }
}

private struct FullScreenChargeMapView: View {
    let coordinate: CLLocationCoordinate2D
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var mapStyle = DriveMapView.MapStyleChoice.standard

    init(coordinate: CLLocationCoordinate2D, title: String) {
        self.coordinate = coordinate
        self.title = title
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 3500,
            longitudinalMeters: 3500
        )
        _position = State(initialValue: .region(region))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(position: $position, interactionModes: .all) {
                    Marker(title, coordinate: coordinate)
                        .tint(.green)
                }
                .mapStyle(mapStyle.style)
                .mapControls {
                    MapCompass()
                    MapPitchToggle()
                    MapScaleView()
                }

                VStack(alignment: .trailing, spacing: 12) {
                    Picker("Style", selection: $mapStyle) {
                        ForEach(DriveMapView.MapStyleChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

                    Button {
                        withAnimation {
                            let region = MKCoordinateRegion(
                                center: coordinate,
                                latitudinalMeters: 3500,
                                longitudinalMeters: 3500
                            )
                            position = .region(region)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.viewfinder")
                            Text("Recenter")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                    }
                }
                .padding()
            }
            .navigationTitle("Charging Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct ChargeHeaderCard: View {
    let charge: ChargeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Charge Session")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(charge.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                }
                Spacer()
                if let end = charge.endDate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Ended")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(end.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bolt.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(charge.address ?? "Unknown Charger Location")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Spacer()
                if let cost = charge.cost, cost > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total Cost")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("$\(cost.formatted(.number.precision(.fractionLength(2))))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ChargeMetricsGrid: View {
    let charge: ChargeSummary
    let points: [ChargePoint]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                title: "Energy Added",
                value: "+\(charge.energyAddedKWh.formatted(.number.precision(.fractionLength(1)))) kWh",
                systemImage: "bolt.fill"
            )

            MetricCard(
                title: "Duration",
                value: formatDuration(minutes: charge.durationMinutes),
                systemImage: "clock"
            )

            if let batteryChange = batteryChangeText {
                MetricCard(
                    title: "Battery Gained",
                    value: batteryChange,
                    systemImage: "battery.100"
                )
            }

            if let rangeAdded = rangeAddedText {
                MetricCard(
                    title: "Range Added",
                    value: rangeAdded,
                    systemImage: "gauge.with.needle"
                )
            }

            if let maxPower = points.compactMap(\.chargerPowerKW).max(), maxPower > 0 {
                MetricCard(
                    title: "Peak Power",
                    value: "\(maxPower.formatted(.number.precision(.fractionLength(0)))) kW",
                    systemImage: "bolt.badge.clock"
                )
            }

            if let used = charge.energyUsedKWh, used > 0 {
                let efficiency = (charge.energyAddedKWh / used) * 100.0
                MetricCard(
                    title: "Efficiency",
                    value: "\(efficiency.formatted(.number.precision(.fractionLength(0))))%",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }

            if let maxCurrent = points.compactMap(\.chargerActualCurrent).max(), maxCurrent > 0,
               let maxVoltage = points.compactMap(\.chargerVoltage).max(), maxVoltage > 0 {
                MetricCard(
                    title: "Max Current/Volt",
                    value: "\(Int(maxCurrent))A / \(Int(maxVoltage))V",
                    systemImage: "waveform.path.ecg"
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

private struct ChargeTelemetryChartSection: View {
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

private struct ChargePowerChartView: View {
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

private struct ChargeBatteryChartView: View {
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

private struct ChargeEnergyChartView: View {
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

private struct ChargeVoltageCurrentChartView: View {
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

private struct SettingsTab: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Grafana") {
                    TextField("https://grafana.yourdomain.com", text: $viewModel.serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("Grafana API Token", text: $viewModel.apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("TeslaMate Datasource") {
                    TextField("Datasource UID", text: $viewModel.datasourceUID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Car ID", value: $viewModel.carID, format: .number)
                        .keyboardType(.numberPad)
                }

                Section {
                    Button("Save and Reload") {
                        Task { await viewModel.loadAll() }
                    }
                    .disabled(!viewModel.isConfigured)
                }

                Section("Notes") {
                    Text("This app reads raw data through Grafana's query API and renders native charts in SwiftUI. No WebView is used.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct MetricsCards: View {
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

private struct MetricCard: View {
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
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DailyDistanceChart: View {
    let points: [DailyValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Distance (14 days)")
                    .font(.headline)
                Spacer()
                let totalMiles = points.map(\.value).reduce(0, +)
                Text("Total: \(totalMiles.formatted(.number.precision(.fractionLength(1)))) mi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Distance (mi)", point.value)
                )
                .foregroundStyle(.blue.gradient)
                .annotation(position: .top, alignment: .center) {
                    if point.value > 0.1 {
                        Text(point.value >= 10 ? "\(point.value.formatted(.number.precision(.fractionLength(0))))" : "\(point.value.formatted(.number.precision(.fractionLength(1))))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DailyChargingChart: View {
    let points: [DailyValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Charging (14 days)")
                    .font(.headline)
                Spacer()
                let totalKWh = points.map(\.value).reduce(0, +)
                Text("Total: \(totalKWh.formatted(.number.precision(.fractionLength(1)))) kWh")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Chart(points) { point in
                AreaMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Energy (kWh)", point.value)
                )
                .foregroundStyle(.green.opacity(0.25))

                LineMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Energy (kWh)", point.value)
                )
                .foregroundStyle(.green)

                PointMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Energy (kWh)", point.value)
                )
                .foregroundStyle(.green)
                .annotation(position: .top, alignment: .center) {
                    if point.value > 0.1 {
                        Text(point.value >= 10 ? "\(point.value.formatted(.number.precision(.fractionLength(0))))" : "\(point.value.formatted(.number.precision(.fractionLength(1))))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @AppStorage("serverURL") var serverURL = ""
    @AppStorage("apiToken") var apiToken = ""
    @AppStorage("datasourceUID") var datasourceUID = ""
    @AppStorage("carID") var carID = 1

    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var summary: VehicleSummary
    @Published var driveDistanceDaily: [DailyValue]
    @Published var chargingEnergyDaily: [DailyValue]
    @Published var recentDrives: [DriveSummary]
    @Published var recentCharges: [ChargeSummary]
    @Published var isLoadingMoreDrives = false
    @Published var isLoadingMoreCharges = false
    @Published var canLoadMoreDrives = true
    @Published var canLoadMoreCharges = true

    private let pageSize = 20
    private var drivesOffset = 0
    private var chargesOffset = 0

    private var drivePositionsCache: [Int: [DrivePositionPoint]] = [:]
    private var chargePointsCache: [Int: [ChargePoint]] = [:]

    init() {
        self.summary = DataCache.loadSummary() ?? .empty
        self.driveDistanceDaily = DataCache.loadDailyDistance()
        self.chargingEnergyDaily = DataCache.loadDailyCharging()
        self.recentDrives = DataCache.loadRecentDrives()
        self.recentCharges = DataCache.loadRecentCharges()
        self.drivesOffset = self.recentDrives.count
        self.chargesOffset = self.recentCharges.count
    }

    var isConfigured: Bool {
        URLBuilder.baseURL(from: serverURL) != nil && !apiToken.isEmpty && !datasourceUID.isEmpty && carID > 0
    }

    var hasDashboardData: Bool {
        summary.batteryLevel > 0 || !driveDistanceDaily.isEmpty || !chargingEnergyDaily.isEmpty
    }

    func loadAll() async {
        guard isConfigured else { return }
        isLoading = true
        errorMessage = nil

        let client: GrafanaClient
        do {
            client = try makeClient()
        } catch {
            handleTaskError(error)
            isLoading = false
            return
        }

        do { try await loadSummary(client: client) } catch { handleTaskError(error) }
        do { try await loadDistance(client: client) } catch { handleTaskError(error) }
        do { try await loadCharging(client: client) } catch { handleTaskError(error) }
        do { try await loadDrives(client: client, reset: true) } catch { handleTaskError(error) }
        do { try await loadRecentCharges(client: client, reset: true) } catch { handleTaskError(error) }

        isLoading = false
    }

    func loadDrivesOnly() async {
        guard isConfigured else { return }
        do {
            let client = try makeClient()
            try await loadDrives(client: client, reset: true)
        } catch {
            handleTaskError(error)
        }
    }

    func loadChargingOnly() async {
        guard isConfigured else { return }
        do {
            let client = try makeClient()
            try await loadRecentCharges(client: client, reset: true)
        } catch {
            handleTaskError(error)
        }
    }

    func loadMoreDrivesIfNeeded(currentItem: DriveSummary) async {
        guard canLoadMoreDrives,
              !isLoadingMoreDrives,
              recentDrives.last?.id == currentItem.id
        else { return }

        do {
            let client = try makeClient()
            try await loadDrives(client: client, reset: false)
        } catch {
            handleTaskError(error)
        }
    }

    func loadMoreChargesIfNeeded(currentItem: ChargeSummary) async {
        guard canLoadMoreCharges,
              !isLoadingMoreCharges,
              recentCharges.last?.id == currentItem.id
        else { return }

        do {
            let client = try makeClient()
            try await loadRecentCharges(client: client, reset: false)
        } catch {
            handleTaskError(error)
        }
    }

    private func handleTaskError(_ error: Error) {
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        let msg = error.localizedDescription
        if msg.lowercased().contains("cancelled") || msg.lowercased().contains("canceled") { return }
        self.errorMessage = msg
    }

    func loadDrivePositions(driveID: Int) async throws -> [DrivePositionPoint] {
        if let cached = drivePositionsCache[driveID], !cached.isEmpty {
            return cached
        }

        let client = try makeClient()
        let sql = """
        SELECT
            date,
            latitude,
            longitude,
            speed,
            power,
            battery_level,
            ideal_battery_range_km,
            elevation,
            outside_temp,
            odometer
        FROM positions
        WHERE drive_id = \(driveID)
        ORDER BY date ASC
        """

        let rows = try await client.queryRows(sql: sql)
        let points: [DrivePositionPoint] = rows.compactMap { row in
            guard let date = row.dateValue(for: "date"),
                  let lat = row.doubleValue(for: "latitude"),
                  let lon = row.doubleValue(for: "longitude")
            else { return nil }

            return DrivePositionPoint(
                date: date,
                latitude: lat,
                longitude: lon,
                speedKmH: row.doubleValue(for: "speed"),
                powerKW: row.doubleValue(for: "power"),
                batteryLevel: row.doubleValue(for: "battery_level"),
                idealRangeKm: row.doubleValue(for: "ideal_battery_range_km"),
                elevationM: row.doubleValue(for: "elevation"),
                outsideTempC: row.doubleValue(for: "outside_temp"),
                odometerKm: row.doubleValue(for: "odometer")
            )
        }

        drivePositionsCache[driveID] = points
        return points
    }

    func loadChargePoints(processID: Int) async throws -> [ChargePoint] {
        if let cached = chargePointsCache[processID], !cached.isEmpty {
            return cached
        }

        let client = try makeClient()
        let sql = """
        SELECT
            date,
            battery_level,
            charge_energy_added,
            charger_power,
            charger_voltage,
            charger_actual_current,
            ideal_battery_range_km,
            outside_temp
        FROM charges
        WHERE charging_process_id = \(processID)
        ORDER BY date ASC
        """

        let rows = try await client.queryRows(sql: sql)
        let points: [ChargePoint] = rows.compactMap { row in
            guard let date = row.dateValue(for: "date") else { return nil }
            return ChargePoint(
                date: date,
                batteryLevel: row.doubleValue(for: "battery_level"),
                chargeEnergyAdded: row.doubleValue(for: "charge_energy_added"),
                chargerPowerKW: row.doubleValue(for: "charger_power"),
                chargerVoltage: row.doubleValue(for: "charger_voltage"),
                chargerActualCurrent: row.doubleValue(for: "charger_actual_current"),
                idealRangeKm: row.doubleValue(for: "ideal_battery_range_km"),
                outsideTempC: row.doubleValue(for: "outside_temp")
            )
        }

        chargePointsCache[processID] = points
        return points
    }

    private func makeClient() throws -> GrafanaClient {
        guard let url = URLBuilder.baseURL(from: serverURL) else {
            throw DashboardError.invalidConfiguration
        }
        return GrafanaClient(baseURL: url, apiToken: apiToken, datasourceUID: datasourceUID)
    }

    private func loadSummary(client: GrafanaClient) async throws {
        let sql = """
        SELECT date, odometer, ideal_battery_range_km, battery_level
        FROM positions
        WHERE car_id = \(carID)
        ORDER BY date DESC
        LIMIT 1
        """

        let rows = try await client.queryRows(sql: sql)
        guard let row = rows.first else { return }

        let newSummary = VehicleSummary(
            batteryLevel: row.doubleValue(for: "battery_level") ?? 0,
            idealRangeKm: row.doubleValue(for: "ideal_battery_range_km") ?? 0,
            odometerKm: row.doubleValue(for: "odometer") ?? 0,
            lastUpdate: row.dateValue(for: "date") ?? .now
        )
        summary = newSummary
        DataCache.saveSummary(newSummary)
    }

    private func loadDistance(client: GrafanaClient) async throws {
        let sql = """
        SELECT date_trunc('day', start_date) AS day, SUM(distance) AS value
        FROM drives
        WHERE car_id = \(carID)
          AND start_date >= now() - interval '14 days'
        GROUP BY 1
        ORDER BY 1
        """

        let rows = try await client.queryRows(sql: sql)
        let points = rows.compactMap { row -> DailyValue? in
            guard let day = row.dateValue(for: "day"), let value = row.doubleValue(for: "value") else { return nil }
            return DailyValue(day: day, value: value * 0.621371)
        }
        driveDistanceDaily = points
        DataCache.saveDailyDistance(points)
    }

    private func loadCharging(client: GrafanaClient) async throws {
        let sql = """
        SELECT date_trunc('day', start_date) AS day, SUM(charge_energy_added) AS value
        FROM charging_processes
        WHERE car_id = \(carID)
          AND start_date >= now() - interval '14 days'
        GROUP BY 1
        ORDER BY 1
        """

        let rows = try await client.queryRows(sql: sql)
        let points = rows.compactMap { row -> DailyValue? in
            guard let day = row.dateValue(for: "day"), let value = row.doubleValue(for: "value") else { return nil }
            return DailyValue(day: day, value: value)
        }
        chargingEnergyDaily = points
        DataCache.saveDailyCharging(points)
    }

    private func loadDrives(client: GrafanaClient, reset: Bool) async throws {
        if reset {
            drivesOffset = 0
            canLoadMoreDrives = true
        }

        guard canLoadMoreDrives else { return }
        isLoadingMoreDrives = !reset
        defer { isLoadingMoreDrives = false }

        let sql = """
        SELECT
            d.id,
            d.start_date,
            d.end_date,
            EXTRACT(EPOCH FROM (COALESCE(d.end_date, d.start_date) - d.start_date)) / 60.0 AS duration_minutes,
            d.distance,
            d.speed_max,
            d.power_max,
            d.power_min,
            d.start_ideal_range_km,
            d.end_ideal_range_km,
            d.outside_temp_avg,
            d.inside_temp_avg,
            COALESCE(start_geofence.name, start_address.name, start_address.road) AS start_address,
            COALESCE(end_geofence.name, end_address.name, end_address.road) AS end_address
        FROM drives d
        LEFT JOIN addresses start_address ON d.start_address_id = start_address.id
        LEFT JOIN addresses end_address ON d.end_address_id = end_address.id
        LEFT JOIN geofences start_geofence ON d.start_geofence_id = start_geofence.id
        LEFT JOIN geofences end_geofence ON d.end_geofence_id = end_geofence.id
        WHERE d.car_id = \(carID)
        ORDER BY d.start_date DESC
        LIMIT \(pageSize)
        OFFSET \(drivesOffset)
        """

        let rows = try await client.queryRows(sql: sql)
        let newDrives: [DriveSummary] = rows.compactMap { row in
            guard let id = row.intValue(for: "id"),
                  let startDate = row.dateValue(for: "start_date") else { return nil }
            return DriveSummary(
                id: id,
                startDate: startDate,
                endDate: row.dateValue(for: "end_date"),
                durationMinutes: Int((row.doubleValue(for: "duration_minutes") ?? 0).rounded()),
                distanceKm: row.doubleValue(for: "distance") ?? 0,
                speedMaxKmH: row.doubleValue(for: "speed_max"),
                powerMaxKW: row.doubleValue(for: "power_max"),
                powerMinKW: row.doubleValue(for: "power_min"),
                startIdealRangeKm: row.doubleValue(for: "start_ideal_range_km"),
                endIdealRangeKm: row.doubleValue(for: "end_ideal_range_km"),
                outsideTempAvgC: row.doubleValue(for: "outside_temp_avg"),
                insideTempAvgC: row.doubleValue(for: "inside_temp_avg"),
                startAddress: row.stringValue(for: "start_address"),
                endAddress: row.stringValue(for: "end_address")
            )
        }

        if reset {
            recentDrives = newDrives
            drivesOffset = newDrives.count
            DataCache.saveRecentDrives(newDrives)
        } else {
            recentDrives.append(contentsOf: newDrives)
            drivesOffset += newDrives.count
        }

        canLoadMoreDrives = newDrives.count == pageSize
    }

    private func loadRecentCharges(client: GrafanaClient, reset: Bool) async throws {
        if reset {
            chargesOffset = 0
            canLoadMoreCharges = true
        }

        guard canLoadMoreCharges else { return }
        isLoadingMoreCharges = !reset
        defer { isLoadingMoreCharges = false }

        let sql = """
        SELECT
            c.id,
            c.start_date,
            c.end_date,
            EXTRACT(EPOCH FROM (COALESCE(c.end_date, c.start_date) - c.start_date)) / 60.0 AS duration_minutes,
            c.charge_energy_added,
            c.charge_energy_used,
            c.start_ideal_range_km,
            c.end_ideal_range_km,
            c.start_battery_level,
            c.end_battery_level,
            c.outside_temp_avg,
            c.cost,
            COALESCE(g.name, a.name, a.road) AS address,
            p.latitude,
            p.longitude
        FROM charging_processes c
        LEFT JOIN addresses a ON c.address_id = a.id
        LEFT JOIN geofences g ON c.geofence_id = g.id
        LEFT JOIN positions p ON c.position_id = p.id
        WHERE c.car_id = \(carID)
        ORDER BY c.start_date DESC
        LIMIT \(pageSize)
        OFFSET \(chargesOffset)
        """

        let rows = try await client.queryRows(sql: sql)
        let newCharges: [ChargeSummary] = rows.compactMap { row in
            guard let id = row.intValue(for: "id"),
                  let startDate = row.dateValue(for: "start_date") else { return nil }
            return ChargeSummary(
                id: id,
                startDate: startDate,
                endDate: row.dateValue(for: "end_date"),
                durationMinutes: Int((row.doubleValue(for: "duration_minutes") ?? 0).rounded()),
                energyAddedKWh: row.doubleValue(for: "charge_energy_added") ?? 0,
                energyUsedKWh: row.doubleValue(for: "charge_energy_used"),
                startBatteryLevel: row.doubleValue(for: "start_battery_level"),
                endBatteryLevel: row.doubleValue(for: "end_battery_level"),
                startIdealRangeKm: row.doubleValue(for: "start_ideal_range_km"),
                endIdealRangeKm: row.doubleValue(for: "end_ideal_range_km"),
                outsideTempAvgC: row.doubleValue(for: "outside_temp_avg"),
                cost: row.doubleValue(for: "cost"),
                address: row.stringValue(for: "address"),
                latitude: row.doubleValue(for: "latitude"),
                longitude: row.doubleValue(for: "longitude")
            )
        }

        if reset {
            recentCharges = newCharges
            chargesOffset = newCharges.count
            DataCache.saveRecentCharges(newCharges)
        } else {
            recentCharges.append(contentsOf: newCharges)
            chargesOffset += newCharges.count
        }

        canLoadMoreCharges = newCharges.count == pageSize
    }
}

private enum DataCache {
    private static let summaryKey = "cached_vehicle_summary"
    private static let distanceKey = "cached_drive_distance_daily"
    private static let chargingKey = "cached_charging_energy_daily"
    private static let drivesKey = "cached_recent_drives"
    private static let chargesKey = "cached_recent_charges"

    static func saveSummary(_ summary: VehicleSummary) {
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: summaryKey)
        }
    }

    static func loadSummary() -> VehicleSummary? {
        guard let data = UserDefaults.standard.data(forKey: summaryKey),
              let summary = try? JSONDecoder().decode(VehicleSummary.self, from: data) else {
            return nil
        }
        return summary
    }

    static func saveDailyDistance(_ list: [DailyValue]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: distanceKey)
        }
    }

    static func loadDailyDistance() -> [DailyValue] {
        guard let data = UserDefaults.standard.data(forKey: distanceKey),
              let list = try? JSONDecoder().decode([DailyValue].self, from: data) else {
            return []
        }
        return list
    }

    static func saveDailyCharging(_ list: [DailyValue]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: chargingKey)
        }
    }

    static func loadDailyCharging() -> [DailyValue] {
        guard let data = UserDefaults.standard.data(forKey: chargingKey),
              let list = try? JSONDecoder().decode([DailyValue].self, from: data) else {
            return []
        }
        return list
    }

    static func saveRecentDrives(_ list: [DriveSummary]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: drivesKey)
        }
    }

    static func loadRecentDrives() -> [DriveSummary] {
        guard let data = UserDefaults.standard.data(forKey: drivesKey),
              let list = try? JSONDecoder().decode([DriveSummary].self, from: data) else {
            return []
        }
        return list
    }

    static func saveRecentCharges(_ list: [ChargeSummary]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: chargesKey)
        }
    }

    static func loadRecentCharges() -> [ChargeSummary] {
        guard let data = UserDefaults.standard.data(forKey: chargesKey),
              let list = try? JSONDecoder().decode([ChargeSummary].self, from: data) else {
            return []
        }
        return list
    }
}

struct VehicleSummary: Codable {
    let batteryLevel: Double
    let idealRangeKm: Double
    let odometerKm: Double
    let lastUpdate: Date

    static let empty = VehicleSummary(batteryLevel: 0, idealRangeKm: 0, odometerKm: 0, lastUpdate: .now)
}

struct DailyValue: Identifiable, Codable {
    var id = UUID()
    let day: Date
    let value: Double

    enum CodingKeys: String, CodingKey {
        case day, value
    }
}

struct DriveSummary: Identifiable, Hashable, Codable {
    let id: Int
    let startDate: Date
    let endDate: Date?
    let durationMinutes: Int
    let distanceKm: Double
    let speedMaxKmH: Double?
    let powerMaxKW: Double?
    let powerMinKW: Double?
    let startIdealRangeKm: Double?
    let endIdealRangeKm: Double?
    let outsideTempAvgC: Double?
    let insideTempAvgC: Double?
    let startAddress: String?
    let endAddress: String?
}

struct DrivePositionPoint: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let latitude: Double
    let longitude: Double
    let speedKmH: Double?
    let powerKW: Double?
    let batteryLevel: Double?
    let idealRangeKm: Double?
    let elevationM: Double?
    let outsideTempC: Double?
    let odometerKm: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var speedMph: Double? {
        speedKmH.map { $0 * 0.621371 }
    }

    var elevationFt: Double? {
        elevationM.map { $0 * 3.28084 }
    }

    var outsideTempF: Double? {
        outsideTempC.map { $0 * 9 / 5 + 32 }
    }
}

struct ChargeSummary: Identifiable, Hashable, Codable {
    let id: Int
    let startDate: Date
    let endDate: Date?
    let durationMinutes: Int
    let energyAddedKWh: Double
    let energyUsedKWh: Double?
    let startBatteryLevel: Double?
    let endBatteryLevel: Double?
    let startIdealRangeKm: Double?
    let endIdealRangeKm: Double?
    let outsideTempAvgC: Double?
    let cost: Double?
    let address: String?
    let latitude: Double?
    let longitude: Double?
}

struct ChargePoint: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let batteryLevel: Double?
    let chargeEnergyAdded: Double?
    let chargerPowerKW: Double?
    let chargerVoltage: Double?
    let chargerActualCurrent: Double?
    let idealRangeKm: Double?
    let outsideTempC: Double?

    var idealRangeMiles: Double? {
        idealRangeKm.map { $0 * 0.621371 }
    }

    var outsideTempF: Double? {
        outsideTempC.map { $0 * 9 / 5 + 32 }
    }
}

private struct GrafanaClient {
    let baseURL: URL
    let apiToken: String
    let datasourceUID: String

    func queryRows(sql: String) async throws -> [GrafanaRow] {
        guard let url = URL(string: "/api/ds/query", relativeTo: baseURL) else {
            throw DashboardError.invalidConfiguration
        }

        let body = GrafanaQueryRequest(
            queries: [
                .init(
                    refId: "A",
                    datasource: .init(type: "grafana-postgresql-datasource", uid: datasourceUID),
                    format: "table",
                    rawSql: sql,
                    intervalMs: 60000,
                    maxDataPoints: 5000
                )
            ],
            from: "now-5y",
            to: "now"
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DashboardError.networkError("No HTTP response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw DashboardError.networkError("Grafana error \(httpResponse.statusCode): \(message)")
        }

        let decoded = try JSONDecoder().decode(GrafanaQueryResponse.self, from: data)
        guard let frame = decoded.results["A"]?.frames.first else {
            return []
        }
        return GrafanaRowMapper.rows(from: frame)
    }
}

private struct GrafanaQueryRequest: Encodable {
    struct Query: Encodable {
        struct Datasource: Encodable {
            let type: String
            let uid: String
        }

        let refId: String
        let datasource: Datasource
        let format: String
        let rawSql: String
        let intervalMs: Int
        let maxDataPoints: Int
    }

    let queries: [Query]
    let from: String
    let to: String
}

private struct GrafanaQueryResponse: Decodable {
    let results: [String: GrafanaResult]
}

private struct GrafanaResult: Decodable {
    let frames: [GrafanaFrame]
}

private struct GrafanaFrame: Decodable {
    struct Schema: Decodable {
        struct Field: Decodable {
            let name: String
            let type: String
        }

        let fields: [Field]
    }

    struct ValueContainer: Decodable {
        let values: [[GrafanaValue]]
    }

    let schema: Schema
    let data: ValueContainer
}

private enum GrafanaValue: Decodable {
    case string(String)
    case number(Double)
    case integer(Int)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let intValue = try? container.decode(Int.self) {
            self = .integer(intValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                GrafanaValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported value type")
            )
        }
    }
}

private struct GrafanaRow {
    let valuesByField: [String: GrafanaValue]

    func doubleValue(for field: String) -> Double? {
        switch valuesByField[field] {
        case .number(let value):
            return value
        case .integer(let value):
            return Double(value)
        case .string(let value):
            return Double(value)
        default:
            return nil
        }
    }

    func intValue(for field: String) -> Int? {
        switch valuesByField[field] {
        case .integer(let value):
            return value
        case .number(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    func stringValue(for field: String) -> String? {
        switch valuesByField[field] {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        case .integer(let value):
            return String(value)
        default:
            return nil
        }
    }

    func dateValue(for field: String) -> Date? {
        switch valuesByField[field] {
        case .number(let value):
            return Date(timeIntervalSince1970: value / 1000)
        case .integer(let value):
            return Date(timeIntervalSince1970: Double(value) / 1000)
        case .string(let value):
            return ISO8601DateFormatter.withFractionalSeconds.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        default:
            return nil
        }
    }
}

private enum GrafanaRowMapper {
    static func rows(from frame: GrafanaFrame) -> [GrafanaRow] {
        let fields = frame.schema.fields.map(\.name)
        guard !fields.isEmpty else { return [] }
        guard let rowCount = frame.data.values.first?.count else { return [] }

        var rows: [GrafanaRow] = []
        rows.reserveCapacity(rowCount)

        for rowIndex in 0..<rowCount {
            var map: [String: GrafanaValue] = [:]
            for (fieldIndex, fieldName) in fields.enumerated() {
                guard fieldIndex < frame.data.values.count,
                      rowIndex < frame.data.values[fieldIndex].count
                else { continue }

                map[fieldName] = frame.data.values[fieldIndex][rowIndex]
            }
            rows.append(GrafanaRow(valuesByField: map))
        }

        return rows
    }
}

private enum DashboardError: LocalizedError {
    case invalidConfiguration
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid configuration. Check URL, token, datasource UID, and car ID."
        case .networkError(let message):
            return message
        }
    }
}

private enum URLBuilder {
    static func baseURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\(trimmed)"

        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else {
            return nil
        }

        return url
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension Double {
    var miles: Double {
        self * 0.621371
    }

    var fahrenheit: Double {
        self * 9.0 / 5.0 + 32.0
    }

    var feet: Double {
        self * 3.28084
    }
}

