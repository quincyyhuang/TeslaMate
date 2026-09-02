import Foundation

enum DateFilterOption: Hashable, Identifiable {
    case all
    case last24Hours
    case last3Days
    case lastWeek
    case lastMonth
    case custom(start: Date, end: Date)

    var id: String {
        switch self {
        case .all: return "all"
        case .last24Hours: return "24h"
        case .last3Days: return "3d"
        case .lastWeek: return "7d"
        case .lastMonth: return "30d"
        case .custom: return "custom"
        }
    }

    var label: String {
        switch self {
        case .all: return "All"
        case .last24Hours: return "24 Hours"
        case .last3Days: return "3 Days"
        case .lastWeek: return "7 Days"
        case .lastMonth: return "30 Days"
        case .custom(let start, let end):
            let f = DateFormatter()
            f.dateFormat = "M/d"
            return "\(f.string(from: start)) – \(f.string(from: end))"
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    func sqlCondition(column: String) -> String? {
        switch self {
        case .all:
            return nil
        case .last24Hours:
            return "\(column) >= now() - interval '24 hours'"
        case .last3Days:
            return "\(column) >= now() - interval '3 days'"
        case .lastWeek:
            return "\(column) >= now() - interval '7 days'"
        case .lastMonth:
            return "\(column) >= now() - interval '30 days'"
        case .custom(let start, let end):
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let startStr = f.string(from: start)
            let endStr = f.string(from: end)
            return "\(column) >= '\(startStr)' AND \(column) <= '\(endStr)'"
        }
    }
}
