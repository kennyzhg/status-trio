import Foundation
import XCTest
@testable import StatusTrioCore

// MARK: - Fakes

private final class FakeWeatherClient: WeatherForecastFetching, @unchecked Sendable {
    var forecastResult: Result<[WeatherDay], WeatherFailure> = .success([])
    var cityResult: Result<[QWeatherCity], WeatherFailure> = .success([])
    private(set) var forecastLocations: [WeatherLocation] = []
    private(set) var cityQueries: [String] = []

    func threeDayForecast(for location: WeatherLocation, credentials: QWeatherCredentials,
                          language: String) async throws -> [WeatherDay] {
        forecastLocations.append(location)
        return try forecastResult.get()
    }

    func lookupCities(named query: String, credentials: QWeatherCredentials,
                      language: String) async throws -> [QWeatherCity] {
        cityQueries.append(query)
        return try cityResult.get()
    }
}

@MainActor
private final class FakeLocator: WeatherLocating {
    var location: WeatherLocation?
    private(set) var requests = 0
    init(_ location: WeatherLocation?) { self.location = location }
    func currentLocation() async -> WeatherLocation? {
        requests += 1
        return location
    }
}

private let sampleDays = [
    WeatherDay(date: "2026-11-05", high: 18, low: 9, iconCode: "100", text: "晴"),
    WeatherDay(date: "2026-11-06", high: 15, low: 7, iconCode: "305", text: "小雨"),
    WeatherDay(date: "2026-11-07", high: 12, low: 3, iconCode: "101", text: "多云")
]

// MARK: - Client

final class QWeatherClientTests: XCTestCase {
    func testHostIsNormalizedAndValidated() {
        XCTAssertEqual(QWeatherClient.baseURL(host: "abc.re.qweatherapi.com")?.absoluteString,
                       "https://abc.re.qweatherapi.com")
        XCTAssertEqual(QWeatherClient.baseURL(host: " https://abc.qweatherapi.com/v7/ ")?.absoluteString,
                       "https://abc.qweatherapi.com")
        XCTAssertNil(QWeatherClient.baseURL(host: ""))
        XCTAssertNil(QWeatherClient.baseURL(host: "bad host?x=1"))
    }

    func testForecastRequestCarriesTheKeyInAHeaderAndRoundedCoordinates() async throws {
        let recorded = RecordedRequest()
        let body = #"{"code":"200","daily":[{"fxDate":"2026-11-05","tempMax":"18","tempMin":"9","iconDay":"100","textDay":"晴"}]}"#
        let client = QWeatherClient { request in
            recorded.request = request
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let days = try await client.threeDayForecast(
            for: WeatherLocation(name: "", latitude: 39.904987, longitude: 116.405289),
            credentials: QWeatherCredentials(host: "abc.qweatherapi.com", apiKey: "secret"),
            language: "zh"
        )
        XCTAssertEqual(days, [WeatherDay(date: "2026-11-05", high: 18, low: 9, iconCode: "100", text: "晴")])
        let request = try XCTUnwrap(recorded.request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-QW-Api-Key"), "secret")
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://abc.qweatherapi.com/v7/weather/3d?"), url)
        XCTAssertTrue(url.contains("location=116.41,39.90"), url)
        XCTAssertFalse(url.contains("secret"), "the key must never be in the URL")
    }

    func testIncompleteCredentialsNeverTouchTheNetwork() async {
        let client = QWeatherClient { _ in
            XCTFail("no request expected")
            throw URLError(.badURL)
        }
        do {
            _ = try await client.threeDayForecast(
                for: WeatherLocation(name: "", latitude: 1, longitude: 1),
                credentials: QWeatherCredentials(host: "abc.qweatherapi.com", apiKey: ""),
                language: "en"
            )
            XCTFail("expected notConfigured")
        } catch {
            XCTAssertEqual(error as? WeatherFailure, .notConfigured)
        }
    }

    func testFailuresMapFromHTTPStatusAndQWeatherCodes() {
        XCTAssertEqual(QWeatherClient.failure(forHTTPStatus: 401), .unauthorized)
        XCTAssertEqual(QWeatherClient.failure(forHTTPStatus: 403), .unauthorized)
        XCTAssertEqual(QWeatherClient.failure(forHTTPStatus: 429), .quotaExceeded)
        XCTAssertEqual(QWeatherClient.failure(forHTTPStatus: 500), .unavailable)
        XCTAssertNil(QWeatherClient.failure(forCode: "200"))
        XCTAssertEqual(QWeatherClient.failure(forCode: "401"), .unauthorized)
        XCTAssertEqual(QWeatherClient.failure(forCode: "402"), .quotaExceeded)
        XCTAssertEqual(QWeatherClient.failure(forCode: "500"), .unavailable)
        XCTAssertThrowsError(try QWeatherClient.parseForecast(Data(#"{"code":"401"}"#.utf8))) {
            XCTAssertEqual($0 as? WeatherFailure, .unauthorized)
        }
        XCTAssertThrowsError(try QWeatherClient.parseForecast(Data("not json".utf8))) {
            XCTAssertEqual($0 as? WeatherFailure, .unavailable)
        }
    }

    func testForecastKeepsAtMostThreeDaysAndSkipsUnreadableTemperatures() throws {
        let body = #"{"code":"200","daily":[{"fxDate":"d1","tempMax":"1","tempMin":"0","iconDay":"100","textDay":"a"},{"fxDate":"d2","tempMax":"x","tempMin":"0","iconDay":"100","textDay":"b"},{"fxDate":"d3","tempMax":"3","tempMin":"1","iconDay":"100","textDay":"c"},{"fxDate":"d4","tempMax":"4","tempMin":"2","iconDay":"100","textDay":"d"},{"fxDate":"d5","tempMax":"5","tempMin":"3","iconDay":"100","textDay":"e"}]}"#
        let days = try QWeatherClient.parseForecast(Data(body.utf8))
        XCTAssertEqual(days.map(\.date), ["d1", "d3", "d4"])
    }

    func testCityLookupParsesRegionsAndTreatsNotFoundAsEmpty() throws {
        let body = #"{"code":"200","location":[{"id":"101010100","name":"北京","lat":"39.90499","lon":"116.40529","adm2":"北京","adm1":"北京市","country":"中国"}]}"#
        let cities = try QWeatherClient.parseCities(Data(body.utf8))
        XCTAssertEqual(cities.first?.name, "北京")
        XCTAssertEqual(cities.first?.region, "北京市 · 中国")
        XCTAssertEqual(cities.first?.location.latitude ?? 0, 39.90499, accuracy: 0.00001)
        XCTAssertEqual(try QWeatherClient.parseCities(Data(#"{"code":"404"}"#.utf8)), [])
    }
}

private final class RecordedRequest: @unchecked Sendable {
    var request: URLRequest?
}

// MARK: - Controller

@MainActor
final class WeatherControllerTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_793_800_000)
    private let beijing = WeatherLocation(name: "北京", latitude: 39.9, longitude: 116.4)

    private func makeSettings() throws -> SettingsStore {
        let suite = "WeatherControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.weatherAPIHost = "abc.qweatherapi.com"
        return settings
    }

    private func makeController(
        settings: SettingsStore,
        client: FakeWeatherClient,
        locator: FakeLocator,
        key: String = "secret"
    ) -> WeatherController {
        WeatherController(
            settings: settings,
            keyStore: InMemoryWeatherAPIKeyStore(key: key),
            client: client,
            locator: locator,
            now: { [unowned self] in self.clock },
            maxAge: 1800
        )
    }

    private func settle(_ controller: WeatherController) async {
        for _ in 0..<50 where controller.isFetching { await Task.yield() }
    }

    func testMissingKeyReportsNotConfiguredWithoutFetching() async throws {
        let client = FakeWeatherClient()
        let controller = makeController(settings: try makeSettings(), client: client,
                                        locator: FakeLocator(nil), key: "")
        controller.refreshIfNeeded(language: "zh")
        await settle(controller)
        XCTAssertEqual(controller.state, .failed(.notConfigured, previous: nil))
        XCTAssertTrue(client.forecastLocations.isEmpty)
    }

    func testManualCityIsFetchedAndCachedUntilItIsStale() async throws {
        let settings = try makeSettings()
        settings.weatherLocationMode = .manual
        settings.weatherManualLocation = beijing
        let client = FakeWeatherClient()
        client.forecastResult = .success(sampleDays)
        let locator = FakeLocator(nil)
        let controller = makeController(settings: settings, client: client, locator: locator)

        controller.refreshIfNeeded(language: "zh")
        await settle(controller)
        XCTAssertEqual(controller.state.forecast?.days, sampleDays)
        XCTAssertEqual(controller.state.forecast?.locationName, "北京")
        XCTAssertEqual(locator.requests, 0, "manual mode never reads the location")

        clock.addTimeInterval(600)
        controller.refreshIfNeeded(language: "zh")
        await settle(controller)
        XCTAssertEqual(client.forecastLocations.count, 1, "a 10-minute-old forecast is reused")

        clock.addTimeInterval(1300)
        controller.refreshIfNeeded(language: "zh")
        await settle(controller)
        XCTAssertEqual(client.forecastLocations.count, 2, "a 31-minute-old forecast is fetched again")
    }

    func testSettingChangesAndForcedRefreshBypassTheCache() async throws {
        let settings = try makeSettings()
        settings.weatherLocationMode = .manual
        settings.weatherManualLocation = beijing
        let client = FakeWeatherClient()
        client.forecastResult = .success(sampleDays)
        let controller = makeController(settings: settings, client: client, locator: FakeLocator(nil))

        controller.refreshIfNeeded(language: "zh")
        await settle(controller)
        settings.weatherManualLocation = WeatherLocation(name: "上海", latitude: 31.2, longitude: 121.5)
        controller.refreshIfNeeded(language: "zh")
        await settle(controller)
        XCTAssertEqual(client.forecastLocations.map(\.name), ["北京", "上海"])

        controller.refresh(language: "zh")
        await settle(controller)
        XCTAssertEqual(client.forecastLocations.count, 3)
    }

    func testAutomaticModeNamesTheFixAndFallsBackToTheCity() async throws {
        let settings = try makeSettings()
        settings.weatherManualLocation = beijing
        let client = FakeWeatherClient()
        client.forecastResult = .success(sampleDays)
        client.cityResult = .success([QWeatherCity(id: "1", name: "海淀", region: "", latitude: 39.96, longitude: 116.3)])
        let locator = FakeLocator(WeatherLocation(name: "", latitude: 39.96, longitude: 116.30))
        let controller = makeController(settings: settings, client: client, locator: locator)

        controller.refreshIfNeeded(language: "zh")
        await settle(controller)
        XCTAssertEqual(controller.state.forecast?.locationName, "海淀")
        XCTAssertEqual(client.cityQueries, ["116.30,39.96"])

        // Location access gone: the manual city is used instead.
        locator.location = nil
        controller.refresh(language: "zh")
        await settle(controller)
        XCTAssertEqual(client.forecastLocations.last, beijing)
    }

    func testNoLocationAtAllReportsNoLocation() async throws {
        let controller = makeController(settings: try makeSettings(), client: FakeWeatherClient(),
                                        locator: FakeLocator(nil))
        controller.refreshIfNeeded(language: "zh")
        await settle(controller)
        XCTAssertEqual(controller.state, .failed(.noLocation, previous: nil))
    }

    func testFailureKeepsThePreviousForecast() async throws {
        let settings = try makeSettings()
        settings.weatherLocationMode = .manual
        settings.weatherManualLocation = beijing
        let client = FakeWeatherClient()
        client.forecastResult = .success(sampleDays)
        let controller = makeController(settings: settings, client: client, locator: FakeLocator(nil))
        controller.refreshIfNeeded(language: "zh")
        await settle(controller)
        let previous = try XCTUnwrap(controller.state.forecast)

        client.forecastResult = .failure(.quotaExceeded)
        controller.refresh(language: "zh")
        await settle(controller)
        XCTAssertEqual(controller.state, .failed(.quotaExceeded, previous: previous))
    }
}

// MARK: - Panel mapping, symbols, settings

@MainActor
final class WeatherPanelMapperTests: XCTestCase {
    private func localization() throws -> Localization {
        let suite = "WeatherPanelMapperTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return Localization(defaults: defaults, preferredLanguages: ["en"])
    }

    func testDaysAreLabelledTodayTomorrowThenWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 20))!
        let state = WeatherPanelMapper.map(
            .loaded(WeatherForecast(locationName: "Beijing", days: sampleDays, fetchedAt: now)),
            localization: try localization(), now: now, calendar: calendar
        )
        XCTAssertEqual(state.days.map(\.label), ["Today", "Tomorrow", "Sat"])
        XCTAssertEqual(state.days.map(\.symbolName), ["sun.max", "cloud.drizzle", "cloud.sun"])
        XCTAssertEqual(state.subtitle, "Beijing")
        XCTAssertNil(state.message)
        XCTAssertEqual(state.temperatureBounds, 3...18)
    }

    func testFailuresShowAHintAndAnUnnamedFixReadsAsCurrentLocation() throws {
        let localization = try localization()
        let notConfigured = WeatherPanelMapper.map(.failed(.notConfigured, previous: nil), localization: localization)
        XCTAssertEqual(notConfigured.message, localization.string(.weatherNotConfigured))
        XCTAssertTrue(notConfigured.days.isEmpty)

        let forecast = WeatherForecast(locationName: "", days: sampleDays, fetchedAt: Date())
        let stale = WeatherPanelMapper.map(.failed(.unavailable, previous: forecast), localization: localization)
        XCTAssertEqual(stale.days.count, 3, "a failure keeps the last forecast visible")
        XCTAssertEqual(stale.subtitle, localization.string(.weatherCurrentLocation))
        XCTAssertEqual(stale.message, localization.string(.weatherUnavailable))
    }

    func testEveryIconFamilyHasASymbolThatExists() {
        for code in ["100", "101", "104", "150", "151", "300", "302", "305", "307", "399",
                     "400", "404", "499", "500", "502", "900", "901", "999", "x"] {
            let name = WeatherSymbol.name(forQWeatherIcon: code)
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(code) → \(name)")
        }
    }

    func testWeatherIsOffByDefaultAndAppendedToStoredOrders() throws {
        let suite = "WeatherPanelMapperTests.order.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { TestUserDefaults.removeSuite(named: suite) }
        XCTAssertFalse(SettingsStore.defaultEnabledPopupSections.contains(.weather))
        defaults.set(["network", "battery"], forKey: SettingsStore.popupSectionOrderDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.popupSectionOrder.last, .weather)
        XCTAssertFalse(settings.visiblePopupSections.contains(.weather))
    }

    func testWeatherSettingsPersistAndDropInvalidCoordinates() throws {
        let suite = "WeatherPanelMapperTests.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { TestUserDefaults.removeSuite(named: suite) }
        let first = SettingsStore(defaults: defaults)
        XCTAssertEqual(first.weatherLocationMode, .automatic)
        first.weatherAPIHost = "abc.qweatherapi.com"
        first.weatherLocationMode = .manual
        first.weatherManualLocation = WeatherLocation(name: "北京", latitude: 39.9, longitude: 116.4)
        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.weatherAPIHost, "abc.qweatherapi.com")
        XCTAssertEqual(second.weatherLocationMode, .manual)
        XCTAssertEqual(second.weatherManualLocation?.name, "北京")
        XCTAssertNil(defaults.string(forKey: "weatherAPIKey"), "the key is never stored in defaults")

        second.weatherManualLocation = WeatherLocation(name: "x", latitude: 200, longitude: 0)
        XCTAssertNil(SettingsStore(defaults: defaults).weatherManualLocation)
    }
}
