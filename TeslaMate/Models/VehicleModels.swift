import Foundation

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

struct CarInfo: Identifiable, Hashable, Codable {
    let id: Int
    let name: String?
    let model: String?
    let vin: String?

    var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        } else if let model = model, !model.isEmpty {
            return "Tesla Model \(model) (Car #\(id))"
        } else {
            return "Car #\(id)"
        }
    }
}
