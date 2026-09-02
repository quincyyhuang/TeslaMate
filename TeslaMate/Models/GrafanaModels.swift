import Foundation

struct GrafanaDatasource: Identifiable, Hashable, Decodable {
    let id: Int?
    let uid: String
    let name: String
    let type: String
    let isDefault: Bool?
}

struct GrafanaQueryRequest: Encodable {
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

struct GrafanaQueryResponse: Decodable {
    let results: [String: GrafanaResult]
}

struct GrafanaResult: Decodable {
    let frames: [GrafanaFrame]
}

struct GrafanaFrame: Decodable {
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

enum GrafanaValue: Decodable {
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

struct GrafanaRow {
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
        guard let raw = valuesByField[field] else { return nil }
        switch raw {
        case .string(let string):
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: string) {
                return date
            }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: string) {
                return date
            }

            let fallback = DateFormatter()
            fallback.locale = Locale(identifier: "en_US_POSIX")
            fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return fallback.date(from: string)

        case .number(let timestamp):
            if timestamp > 10_000_000_000 {
                return Date(timeIntervalSince1970: timestamp / 1000.0)
            } else {
                return Date(timeIntervalSince1970: timestamp)
            }

        case .integer(let timestamp):
            if timestamp > 10_000_000_000 {
                return Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
            } else {
                return Date(timeIntervalSince1970: Double(timestamp))
            }

        case .null:
            return nil
        }
    }
}

enum GrafanaRowMapper {
    static func rows(from frame: GrafanaFrame) -> [GrafanaRow] {
        let fieldNames = frame.schema.fields.map(\.name)
        let matrix = frame.data.values
        guard !fieldNames.isEmpty, !matrix.isEmpty else { return [] }

        let rowCount = matrix.first?.count ?? 0
        var rows: [GrafanaRow] = []
        rows.reserveCapacity(rowCount)

        for rowIndex in 0..<rowCount {
            var dictionary: [String: GrafanaValue] = [:]
            for (colIndex, fieldName) in fieldNames.enumerated() {
                if colIndex < matrix.count, rowIndex < matrix[colIndex].count {
                    dictionary[fieldName] = matrix[colIndex][rowIndex]
                }
            }
            rows.append(GrafanaRow(valuesByField: dictionary))
        }

        return rows
    }
}
