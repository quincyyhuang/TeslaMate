import Foundation
import SwiftUI
import Combine

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

    @Published var availableCars: [CarInfo] = []
    @Published var availableDatasources: [GrafanaDatasource] = []
    @Published var connectionStatus = ConnectionStatus.idle

    enum ConnectionStatus: Equatable {
        case idle
        case testing
        case success(String)
        case error(String)
    }

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
        self.availableCars = DataCache.loadCars()
        self.drivesOffset = self.recentDrives.count
        self.chargesOffset = self.recentCharges.count
    }

    var isConfigured: Bool {
        URLBuilder.baseURL(from: serverURL) != nil && !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasDashboardData: Bool {
        summary.batteryLevel > 0 || !driveDistanceDaily.isEmpty || !chargingEnergyDaily.isEmpty
    }

    func testAndAutoConfigure() async {
        guard let url = URLBuilder.baseURL(from: serverURL), !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            connectionStatus = .error("Please enter a valid Grafana Server URL and API Token.")
            return
        }

        connectionStatus = .testing
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let client = GrafanaClient(baseURL: url, apiToken: trimmedToken, datasourceUID: datasourceUID.isEmpty ? "teslamate" : datasourceUID)
            let datasources = try await client.fetchDatasources()
            self.availableDatasources = datasources

            let match = datasources.first(where: {
                $0.type.localizedCaseInsensitiveContains("postgres") ||
                $0.name.localizedCaseInsensitiveContains("teslamate") ||
                $0.uid.localizedCaseInsensitiveContains("teslamate")
            }) ?? datasources.first

            guard let ds = match else {
                throw DashboardError.networkError("No datasources found in Grafana.")
            }

            self.datasourceUID = ds.uid

            let queryClient = GrafanaClient(baseURL: url, apiToken: trimmedToken, datasourceUID: ds.uid)
            let carRows = try await queryClient.queryRows(sql: "SELECT id, name, model, vin FROM cars ORDER BY id ASC")
            let cars: [CarInfo] = carRows.compactMap { row in
                guard let id = row.intValue(for: "id") else { return nil }
                return CarInfo(
                    id: id,
                    name: row.stringValue(for: "name"),
                    model: row.stringValue(for: "model"),
                    vin: row.stringValue(for: "vin")
                )
            }

            self.availableCars = cars
            DataCache.saveCars(cars)

            if !cars.isEmpty && !cars.contains(where: { $0.id == carID }) {
                self.carID = cars[0].id
            }

            let carDesc = cars.first(where: { $0.id == carID })?.displayName ?? "Car #\(carID)"
            connectionStatus = .success("Connected! Detected '\(ds.name)' datasource and vehicle: \(carDesc).")

            await loadAll()
        } catch {
            connectionStatus = .error(error.localizedDescription)
        }
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
        let uid = datasourceUID.isEmpty ? "teslamate" : datasourceUID
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return GrafanaClient(baseURL: url, apiToken: token, datasourceUID: uid)
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
