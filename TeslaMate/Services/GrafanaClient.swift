import Foundation

struct GrafanaClient {
    let baseURL: URL
    let apiToken: String
    let datasourceUID: String

    func fetchDatasources() async throws -> [GrafanaDatasource] {
        guard let url = URL(string: "/api/datasources", relativeTo: baseURL) else {
            throw DashboardError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DashboardError.networkError("No HTTP response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw DashboardError.networkError("Grafana error \(httpResponse.statusCode): \(message)")
        }

        return try JSONDecoder().decode([GrafanaDatasource].self, from: data)
    }

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
