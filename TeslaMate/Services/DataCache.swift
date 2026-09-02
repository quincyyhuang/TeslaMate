import Foundation

enum DataCache {
    private static let summaryKey = "cached_vehicle_summary"
    private static let distanceKey = "cached_drive_distance_daily"
    private static let chargingKey = "cached_charging_energy_daily"
    private static let drivesKey = "cached_recent_drives"
    private static let chargesKey = "cached_recent_charges"
    private static let carsKey = "cached_available_cars"

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

    static func saveCars(_ list: [CarInfo]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: carsKey)
        }
    }

    static func loadCars() -> [CarInfo] {
        guard let data = UserDefaults.standard.data(forKey: carsKey),
              let list = try? JSONDecoder().decode([CarInfo].self, from: data) else {
            return []
        }
        return list
    }
}
