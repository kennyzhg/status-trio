import Combine
import Foundation

/// Owns the panel's three-day forecast.
///
/// There is no timer: the panel asks for a refresh when it opens with the
/// Weather section visible, and a forecast younger than `maxAge` for the same
/// configuration is reused. Closing the panel never cancels a fetch already
/// on the wire, but nothing new starts while it is closed.
@MainActor
final class WeatherController: ObservableObject {
    @Published private(set) var state: WeatherState = .idle

    private let settings: SettingsStore
    private let keyStore: WeatherAPIKeyStoring
    private let client: WeatherForecastFetching
    private let locator: WeatherLocating
    private let now: () -> Date
    private let maxAge: TimeInterval

    private var fetchTask: Task<Void, Never>?
    private var loadedSignature: Signature?
    private var settingsCancellable: AnyCancellable?
    /// Names resolved for automatic fixes, keyed by the rounded coordinate,
    /// so a stationary Mac does not look its own city up on every refresh.
    private var resolvedNames: [String: String] = [:]

    private struct Signature: Equatable {
        let host: String
        let key: String
        let mode: WeatherLocationMode
        let manual: WeatherLocation?
        let language: String
    }

    init(
        settings: SettingsStore,
        keyStore: WeatherAPIKeyStoring = KeychainWeatherAPIKeyStore(),
        client: WeatherForecastFetching = QWeatherClient(),
        locator: WeatherLocating? = nil,
        now: @escaping () -> Date = Date.init,
        maxAge: TimeInterval = 30 * 60
    ) {
        self.settings = settings
        self.keyStore = keyStore
        self.client = client
        self.locator = locator ?? CoreLocationWeatherLocator()
        self.now = now
        self.maxAge = maxAge
        // A changed host, key, mode or city makes the cached forecast stale;
        // the next panel open fetches again. Nothing is fetched from here.
        settingsCancellable = Publishers.CombineLatest4(
            settings.$weatherAPIHost.removeDuplicates(),
            settings.$weatherLocationMode.removeDuplicates(),
            settings.$weatherManualLocation.removeDuplicates(),
            settings.$weatherCredentialRevision.removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] _ in self?.loadedSignature = nil }
    }

    var isFetching: Bool { fetchTask != nil }

    /// Called when the panel shows the Weather section.
    func refreshIfNeeded(language: String) {
        let signature = currentSignature(language: language)
        let credentials = QWeatherCredentials(host: signature.host, apiKey: signature.key)
        guard credentials.isComplete else {
            fetchTask?.cancel()
            fetchTask = nil
            loadedSignature = nil
            state = .failed(.notConfigured, previous: nil)
            return
        }
        if case .loaded(let forecast) = state,
           loadedSignature == signature,
           now().timeIntervalSince(forecast.fetchedAt) < maxAge {
            return
        }
        guard fetchTask == nil else { return }
        state = .loading(previous: state.forecast)
        fetchTask = Task { @MainActor [weak self] in
            await self?.fetch(signature: signature, credentials: credentials)
        }
    }

    /// Ignores the cache, e.g. after the user saved new credentials.
    func refresh(language: String) {
        loadedSignature = nil
        refreshIfNeeded(language: language)
    }

    private func currentSignature(language: String) -> Signature {
        Signature(
            host: settings.weatherAPIHost.trimmingCharacters(in: .whitespacesAndNewlines),
            key: keyStore.readKey(),
            mode: settings.weatherLocationMode,
            manual: settings.weatherManualLocation,
            language: language
        )
    }

    private func fetch(signature: Signature, credentials: QWeatherCredentials) async {
        defer { fetchTask = nil }
        let previous = state.forecast
        guard let location = await resolveLocation(signature: signature, credentials: credentials) else {
            state = .failed(.noLocation, previous: previous)
            return
        }
        do {
            let days = try await client.threeDayForecast(
                for: location, credentials: credentials, language: signature.language
            )
            state = .loaded(WeatherForecast(locationName: location.name, days: days, fetchedAt: now()))
            loadedSignature = signature
        } catch let failure as WeatherFailure {
            state = .failed(failure, previous: previous)
        } catch {
            state = .failed(.unavailable, previous: previous)
        }
    }

    private func resolveLocation(
        signature: Signature,
        credentials: QWeatherCredentials
    ) async -> WeatherLocation? {
        let manual = signature.manual.flatMap { $0.isValid ? $0 : nil }
        guard signature.mode == .automatic else { return manual }
        guard let fix = await locator.currentLocation(), fix.isValid else { return manual }
        let key = fix.queryValue + "|" + signature.language
        if let name = resolvedNames[key] {
            return WeatherLocation(name: name, latitude: fix.latitude, longitude: fix.longitude)
        }
        // The city search also accepts `lon,lat`; its first hit names the fix.
        // A failed name lookup keeps the forecast and just leaves the name blank.
        let name = (try? await client.lookupCities(
            named: fix.queryValue, credentials: credentials, language: signature.language
        ))?.first?.name ?? ""
        if !name.isEmpty { resolvedNames[key] = name }
        return WeatherLocation(name: name, latitude: fix.latitude, longitude: fix.longitude)
    }
}
