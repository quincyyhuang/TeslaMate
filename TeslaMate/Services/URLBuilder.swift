import Foundation

enum URLBuilder {
    static func baseURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }
}
