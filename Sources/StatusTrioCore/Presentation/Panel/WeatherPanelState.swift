import Foundation

/// What the panel's Weather section draws. Built only by `WeatherPanelMapper`.
struct WeatherPanelState: Equatable {
    struct Day: Equatable, Identifiable {
        let id: String
        let label: String
        let symbolName: String
        let text: String
        let high: Int
        let low: Int
    }

    let title: String
    /// The location name, or "Current Location" for an unnamed fix.
    let subtitle: String
    let days: [Day]
    /// A status line: loading, a failure, or the setup hint. `nil` when the
    /// days are current.
    let message: String?
    let isLoading: Bool
    let refreshLabel: String
    let trendLabel: String

    static let empty = WeatherPanelState(
        title: "", subtitle: "", days: [], message: nil, isLoading: false,
        refreshLabel: "", trendLabel: ""
    )

    /// The coldest low and warmest high, for scaling the trend lines.
    var temperatureBounds: ClosedRange<Int>? {
        guard let low = days.map(\.low).min(), let high = days.map(\.high).max() else { return nil }
        return low...max(high, low)
    }
}

enum WeatherPanelMapper {
    @MainActor
    static func map(
        _ state: WeatherState,
        localization: Localization,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeatherPanelState {
        let forecast = state.forecast
        let message: String?
        let isLoading: Bool
        switch state {
        case .idle:
            message = localization.string(.weatherLoading)
            isLoading = true
        case .loading:
            message = forecast == nil ? localization.string(.weatherLoading) : nil
            isLoading = true
        case .loaded:
            message = nil
            isLoading = false
        case .failed(let failure, _):
            message = localization.string(failureKey(failure))
            isLoading = false
        }
        let name = forecast?.locationName ?? ""
        return WeatherPanelState(
            title: localization.string(.weatherTitle),
            subtitle: name.isEmpty && forecast != nil
                ? localization.string(.weatherCurrentLocation)
                : name,
            days: (forecast?.days ?? []).map { day in
                WeatherPanelState.Day(
                    id: day.date,
                    label: dayLabel(day.date, localization: localization, now: now, calendar: calendar),
                    symbolName: WeatherSymbol.name(forQWeatherIcon: day.iconCode),
                    text: day.text,
                    high: day.high,
                    low: day.low
                )
            },
            message: message,
            isLoading: isLoading,
            refreshLabel: localization.string(.weatherRefresh),
            trendLabel: localization.string(.weatherTrend)
        )
    }

    static func failureKey(_ failure: WeatherFailure) -> LocalizationKey {
        switch failure {
        case .notConfigured: .weatherNotConfigured
        case .noLocation: .weatherNoLocation
        case .unauthorized: .weatherUnauthorized
        case .quotaExceeded: .weatherQuotaExceeded
        case .unavailable: .weatherUnavailable
        }
    }

    /// "Today", "Tomorrow", then a short weekday in the app's language.
    @MainActor
    static func dayLabel(
        _ date: String,
        localization: Localization,
        now: Date,
        calendar: Calendar
    ) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = calendar.timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: date) else { return date }
        let offset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: day)
        ).day
        switch offset {
        case 0: return localization.string(.weatherToday)
        case 1: return localization.string(.weatherTomorrow)
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: localization.resolvedLanguage.rawValue)
            formatter.setLocalizedDateFormatFromTemplate("EEE")
            return formatter.string(from: day)
        }
    }
}
