import Foundation

/// Minimal Home Assistant REST client (long-lived access token).
struct HomeAssistantClient {
    struct EntityState {
        var state: String
        var attributes: [String: Any]
        var lastChanged: Date? = nil
    }

    let baseURL: URL
    let token: String
    var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    /// nil when no URL or token has been set, so every HA feature quietly switches off.
    static func configured(_ settings: BridgeSettings) -> HomeAssistantClient? {
        let text = settings.homeAssistantURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = KeychainStore.secret(KeychainStore.homeAssistantAccount)
        guard !text.isEmpty, !token.isEmpty, let url = URL(string: text.hasSuffix("/") ? String(text.dropLast()) : text) else { return nil }
        return HomeAssistantClient(baseURL: url, token: token)
    }

    func state(of entityID: String) async throws -> EntityState {
        let json = try await send("GET", path: "/api/states/\(entityID)") as? [String: Any]
        return EntityState(
            state: json?["state"] as? String ?? "unknown",
            attributes: json?["attributes"] as? [String: Any] ?? [:],
            lastChanged: (json?["last_changed"] as? String).flatMap(Self.parseHADate)
        )
    }

    /// HA writes microseconds ("…:53.960229+00:00"); drop the fraction so any iOS parses it.
    static func parseHADate(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }

    /// `turn_on` for whatever domain the entity is in (input_boolean, script, …).
    /// Retries, because a missed snooze/stop means the morning routine doesn't run.
    func turnOn(_ entityID: String, attempts: Int = 3) async throws {
        let domain = entityID.split(separator: ".").first.map(String.init) ?? "homeassistant"
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                _ = try await send("POST", path: "/api/services/\(domain)/turn_on", body: ["entity_id": entityID])
                return
            } catch {
                lastError = error
                if attempt < attempts - 1 { try? await Task.sleep(for: .seconds(2)) }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    /// Creates or updates a state-only entity (e.g. sensor.bedtime_bridge_next_alarm).
    /// It isn't stored by HA, so it reads "unavailable" after an HA restart until the next update.
    func setState(_ entityID: String, state: String, attributes: [String: Any]) async throws {
        _ = try await send("POST", path: "/api/states/\(entityID)", body: ["state": state, "attributes": attributes])
    }

    func hourlyForecast(for weatherEntity: String) async throws -> [ForecastHour] {
        let json = try await send(
            "POST",
            path: "/api/services/weather/get_forecasts",
            query: [URLQueryItem(name: "return_response", value: nil)],
            body: ["entity_id": weatherEntity, "type": "hourly"]
        ) as? [String: Any]
        let response = json?["service_response"] as? [String: Any]
        let entries = (response?[weatherEntity] as? [String: Any])?["forecast"] as? [[String: Any]] ?? []
        let iso = ISO8601DateFormatter()
        return entries.compactMap { entry in
            guard let text = entry["datetime"] as? String, let start = iso.date(from: text) else { return nil }
            return ForecastHour(
                start: start,
                condition: entry["condition"] as? String ?? "",
                temperature: (entry["temperature"] as? NSNumber)?.doubleValue
            )
        }
    }

    private func send(_ method: String, path: String, query: [URLQueryItem]? = nil, body: [String: Any]? = nil) async throws -> Any? {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BridgeError.homeAssistant(http.statusCode, String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data)
    }
}
