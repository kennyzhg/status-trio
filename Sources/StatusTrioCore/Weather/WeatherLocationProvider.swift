import CoreLocation
import Foundation

/// One approximate location fix, or `nil` when location is unavailable.
@MainActor
protocol WeatherLocating: AnyObject {
    /// Never prompts: weather only uses location access the user already gave
    /// (the app asks for it for the Wi-Fi name). Returns `nil` without access.
    func currentLocation() async -> WeatherLocation?
}

/// Reads a kilometre-accuracy fix once per request and stops; there is no
/// continuous tracking. A fix that does not arrive in time yields `nil`, so
/// the caller falls back to the manual city.
@MainActor
final class CoreLocationWeatherLocator: NSObject, WeatherLocating {
    private let manager: CLLocationManager
    private var pending: [CheckedContinuation<WeatherLocation?, Never>] = []
    private var timeoutTask: Task<Void, Never>?
    private let timeout: Duration
    /// The status Core Location last reported. `manager.authorizationStatus`
    /// can block on locationd (see `CoreLocationWiFiNameAuthorizer`), so the
    /// delegate's report is the only source; before it arrives, no access.
    private var isAuthorized = false
    /// Whether Core Location has reported at all. A locator created as the
    /// panel opens is asked for a fix before that first report lands, so the
    /// request waits briefly for it instead of reading "no access".
    private var hasAuthorizationReport = false
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private let authorizationWait: Duration

    init(
        manager: CLLocationManager = CLLocationManager(),
        timeout: Duration = .seconds(10),
        authorizationWait: Duration = .seconds(3)
    ) {
        self.manager = manager
        self.timeout = timeout
        self.authorizationWait = authorizationWait
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async -> WeatherLocation? {
        if !hasAuthorizationReport { await waitForAuthorizationReport() }
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
            guard pending.count == 1 else { return }
            manager.requestLocation()
            timeoutTask = Task { @MainActor [weak self, timeout] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.finish(nil)
            }
        }
    }

    private func waitForAuthorizationReport() async {
        let deadline = Task { @MainActor [weak self, authorizationWait] in
            try? await Task.sleep(for: authorizationWait)
            self?.releaseAuthorizationWaiters()
        }
        await withCheckedContinuation { continuation in
            if hasAuthorizationReport {
                continuation.resume()
            } else {
                authorizationWaiters.append(continuation)
            }
        }
        deadline.cancel()
    }

    private func releaseAuthorizationWaiters() {
        let waiting = authorizationWaiters
        authorizationWaiters = []
        waiting.forEach { $0.resume() }
    }

    private func finish(_ location: WeatherLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let waiting = pending
        pending = []
        waiting.forEach { $0.resume(returning: location) }
    }
}

extension CoreLocationWeatherLocator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let authorized: Bool
        switch status {
        case .authorizedAlways, .authorized:
            authorized = true
        default:
            authorized = false
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isAuthorized = authorized
            self.hasAuthorizationReport = true
            self.releaseAuthorizationWaiters()
            if !authorized { self.finish(nil) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let location = WeatherLocation(name: "", latitude: coordinate.latitude, longitude: coordinate.longitude)
        Task { @MainActor [weak self] in self?.finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.finish(nil) }
    }
}
