import Foundation
import CoreLocation

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
