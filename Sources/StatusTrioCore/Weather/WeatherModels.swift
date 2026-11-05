import Foundation

/// A place the forecast is read for. Coordinates are rounded to two decimals
/// (about 1 km) before they leave the Mac.
struct WeatherLocation: Equatable, Hashable, Sendable, Codable {
    let name: String
    let latitude: Double
    let longitude: Double

    /// `lon,lat`, the coordinate form QWeather expects, at 0.01° precision.
    var queryValue: String {
        String(format: "%.2f,%.2f", longitude, latitude)
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

/// Where the forecast location comes from.
enum WeatherLocationMode: String, CaseIterable, Identifiable, Sendable {
    /// The Mac's approximate location, falling back to the manual city when
    /// location access is unavailable or the reading fails.
    case automatic
    /// Always the city picked in Settings.
    case manual

    var id: Self { self }
}

/// One forecast day as the panel needs it.
struct WeatherDay: Equatable, Sendable {
    /// `yyyy-MM-dd` in the forecast location's own calendar day.
    let date: String
    let high: Int
    let low: Int
    /// QWeather icon code (e.g. `100` sunny), mapped to an SF Symbol for display.
    let iconCode: String
    let text: String
}

struct WeatherForecast: Equatable, Sendable {
    let locationName: String
    let days: [WeatherDay]
    let fetchedAt: Date
}

/// Why a forecast is not available. The cases map to panel copy, never raw
/// server text, so nothing secret or noisy reaches the UI.
enum WeatherFailure: Error, Equatable, Sendable {
    /// No API Host or key yet.
    case notConfigured
    /// Automatic location failed and no manual city is set.
    case noLocation
    /// The key or host was rejected (HTTP 401 or QWeather 401).
    case unauthorized
    /// The key is valid but the project's security settings deny this API or
    /// request (HTTP 403 "Security Restriction", QWeather 403), e.g. a key
    /// that may call the forecast but not the city lookup.
    case restricted
    /// Daily quota or rate limit (HTTP 429 or QWeather 402/429).
    case quotaExceeded
    /// Network, timeout, malformed response or any other server code.
    case unavailable
}

enum WeatherState: Equatable, Sendable {
    case idle
    case loading(previous: WeatherForecast?)
    case loaded(WeatherForecast)
    case failed(WeatherFailure, previous: WeatherForecast?)

    var forecast: WeatherForecast? {
        switch self {
        case .idle: nil
        case .loading(let previous): previous
        case .loaded(let forecast): forecast
        case .failed(_, let previous): previous
        }
    }
}

/// QWeather `lang` values for the app's languages.
enum QWeatherLanguage {
    static func code(for language: AppLanguage) -> String {
        switch language {
        case .english: "en"
        case .simplifiedChinese: "zh"
        case .traditionalChinese: "zh-hant"
        case .japanese: "ja"
        case .korean: "ko"
        case .spanish: "es"
        case .french: "fr"
        case .german: "de"
        case .italian: "it"
        case .brazilianPortuguese: "pt"
        case .russian: "ru"
        case .arabic: "ar"
        }
    }
}

/// QWeather icon codes to SF Symbols that exist on macOS 13.
enum WeatherSymbol {
    static func name(forQWeatherIcon code: String) -> String {
        guard let value = Int(code) else { return "cloud" }
        switch value {
        case 100: return "sun.max"
        case 150: return "moon.stars"
        case 101, 102, 103: return "cloud.sun"
        case 151, 152, 153: return "cloud.moon"
        case 104: return "cloud"
        case 300, 301, 350, 351: return "cloud.sun.rain"
        case 302, 303, 304: return "cloud.bolt.rain"
        case 305, 309, 314, 399: return "cloud.drizzle"
        case 306, 307, 308, 310...313, 315...318: return "cloud.heavyrain"
        case 404, 405, 406, 456: return "cloud.sleet"
        case 400...499: return "cloud.snow"
        case 500, 501, 509, 510, 514, 515: return "cloud.fog"
        case 502...508, 511...513: return "sun.haze"
        case 900: return "thermometer.sun"
        case 901: return "thermometer.snowflake"
        default: return "cloud"
        }
    }
}
