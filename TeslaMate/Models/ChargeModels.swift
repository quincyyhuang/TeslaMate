import Foundation

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
