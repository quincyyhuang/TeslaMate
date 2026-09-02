import Foundation

enum DashboardError: LocalizedError {
    case invalidConfiguration
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Please configure your Grafana server URL and API token in Settings."
        case .networkError(let message):
            return message
        }
    }
}

extension Double {
    var miles: Double {
        self * 0.621371
    }

    var fahrenheit: Double {
        self * 9 / 5 + 32
    }
}
