import Foundation

/// The QWeather account details a request needs.
struct QWeatherCredentials: Equatable, Sendable {
    /// The account's own API Host from the QWeather console, e.g.
    /// `abcxyz.re.qweatherapi.com`. A pasted scheme or trailing path is
    /// tolerated; an empty host means "not configured".
    let host: String
    let apiKey: String

    var isComplete: Bool { QWeatherClient.baseURL(host: host) != nil && !apiKey.isEmpty }
}

struct QWeatherCity: Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    /// Province/state and country, for telling same-named cities apart.
    let region: String
    let latitude: Double
    let longitude: Double

    var location: WeatherLocation {
        WeatherLocation(name: name, latitude: latitude, longitude: longitude)
    }
}

extension WeatherLocation {
    /// Reads `lat,lon` (comma, Chinese comma or whitespace separated), so a
    /// city can be set without the GeoAPI, which some keys may not call.
    static func coordinates(from text: String) -> WeatherLocation? {
        let parts = text
            .replacingOccurrences(of: "，", with: ",")
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]) else { return nil }
        let location = WeatherLocation(
            name: String(format: "%.2f, %.2f", latitude, longitude),
            latitude: latitude,
            longitude: longitude
        )
        return location.isValid ? location : nil
    }
}

protocol WeatherForecastFetching: Sendable {
    func threeDayForecast(
        for location: WeatherLocation,
        credentials: QWeatherCredentials,
        language: String
    ) async throws -> [WeatherDay]

    func lookupCities(
        named query: String,
        credentials: QWeatherCredentials,
        language: String
    ) async throws -> [QWeatherCity]
}

/// Plain HTTPS client for the two QWeather endpoints the panel uses:
/// `/v7/weather/3d` and `/geo/v2/city/lookup`. The key travels in the
/// `X-QW-Api-Key` header, never in the URL.
struct QWeatherClient: WeatherForecastFetching {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let transport: Transport

    init(transport: @escaping Transport = QWeatherClient.defaultTransport) {
        self.transport = transport
    }

    static let defaultTransport: Transport = { request in
        try await URLSession.shared.data(for: request)
    }

    static func baseURL(host rawHost: String) -> URL? {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where host.lowercased().hasPrefix(prefix) {
            host = String(host.dropFirst(prefix.count))
        }
        if let slash = host.firstIndex(of: "/") { host = String(host[..<slash]) }
        guard !host.isEmpty,
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" }),
              let url = URL(string: "https://\(host)") else {
            return nil
        }
        return url
    }

    func threeDayForecast(
        for location: WeatherLocation,
        credentials: QWeatherCredentials,
        language: String
    ) async throws -> [WeatherDay] {
        let data = try await get(
            path: "/v7/weather/3d",
            query: [
                URLQueryItem(name: "location", value: location.queryValue),
                URLQueryItem(name: "lang", value: language),
                URLQueryItem(name: "unit", value: "m")
            ],
            credentials: credentials
        )
        return try Self.parseForecast(data)
    }

    func lookupCities(
        named query: String,
        credentials: QWeatherCredentials,
        language: String
    ) async throws -> [QWeatherCity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let data = try await get(
            path: "/geo/v2/city/lookup",
            query: [
                URLQueryItem(name: "location", value: trimmed),
                URLQueryItem(name: "lang", value: language),
                URLQueryItem(name: "number", value: "5")
            ],
            credentials: credentials
        )
        return try Self.parseCities(data)
    }

    private func get(
        path: String,
        query: [URLQueryItem],
        credentials: QWeatherCredentials
    ) async throws -> Data {
        guard credentials.isComplete,
              let base = Self.baseURL(host: credentials.host),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw WeatherFailure.notConfigured
        }
        components.path = path
        components.queryItems = query
        guard let url = components.url else { throw WeatherFailure.unavailable }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-QW-Api-Key")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw WeatherFailure.unavailable
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Self.failure(forHTTPStatus: http.statusCode)
        }
        return data
    }

    static func failure(forHTTPStatus status: Int) -> WeatherFailure {
        switch status {
        case 401: .unauthorized
        case 403: .restricted
        case 429: .quotaExceeded
        default: .unavailable
        }
    }

    /// QWeather v7 also reports errors in a `code` field on HTTP 200.
    static func failure(forCode code: String) -> WeatherFailure? {
        switch code {
        case "200": nil
        case "401": .unauthorized
        case "403": .restricted
        case "402", "429": .quotaExceeded
        default: .unavailable
        }
    }

    private struct ForecastResponse: Decodable {
        struct Daily: Decodable {
            let fxDate: String
            let tempMax: String
            let tempMin: String
            let iconDay: String
            let textDay: String
        }
        let code: String
        let daily: [Daily]?
    }

    private struct CityResponse: Decodable {
        struct City: Decodable {
            let id: String
            let name: String
            let lat: String
            let lon: String
            let adm1: String?
            let adm2: String?
            let country: String?
        }
        let code: String
        let location: [City]?
    }

    static func parseForecast(_ data: Data) throws -> [WeatherDay] {
        guard let response = try? JSONDecoder().decode(ForecastResponse.self, from: data) else {
            throw WeatherFailure.unavailable
        }
        if let failure = failure(forCode: response.code) { throw failure }
        let days = (response.daily ?? []).compactMap { daily -> WeatherDay? in
            guard let high = Int(daily.tempMax), let low = Int(daily.tempMin) else { return nil }
            return WeatherDay(date: daily.fxDate, high: high, low: low,
                              iconCode: daily.iconDay, text: daily.textDay)
        }
        guard !days.isEmpty else { throw WeatherFailure.unavailable }
        return Array(days.prefix(3))
    }

    static func parseCities(_ data: Data) throws -> [QWeatherCity] {
        guard let response = try? JSONDecoder().decode(CityResponse.self, from: data) else {
            throw WeatherFailure.unavailable
        }
        // 404 here means "no city by that name", which is an empty result.
        if response.code == "404" { return [] }
        if let failure = failure(forCode: response.code) { throw failure }
        return (response.location ?? []).compactMap { city in
            guard let lat = Double(city.lat), let lon = Double(city.lon) else { return nil }
            let region = [city.adm1, city.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty && $0 != city.name }
                .joined(separator: " · ")
            return QWeatherCity(id: city.id, name: city.name, region: region,
                                latitude: lat, longitude: lon)
        }
    }
}
