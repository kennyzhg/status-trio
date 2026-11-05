import Combine
import Foundation
import XCTest
@testable import StatusTrioCore

/// Issue #255: separate fallback-poll intervals on battery and on power.
@MainActor
final class RefreshIntervalByPowerSourceTests: XCTestCase {
    private let onBattery = BatteryStatus(rawPercentage: 60, isPresent: true, isCharging: false,
                                          isLowPowerMode: false, isConnectedToPower: false)
    private let pluggedIn = BatteryStatus(rawPercentage: 60, isPresent: true, isCharging: true,
                                          isLowPowerMode: false, isConnectedToPower: true)
    private let noBattery = BatteryStatus(rawPercentage: nil, isPresent: false, isCharging: false,
                                          isLowPowerMode: false, isConnectedToPower: false)

    private func makeDefaults() throws -> UserDefaults {
        let suite = "RefreshIntervalByPowerSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return defaults
    }

    // MARK: Migration

    func testOldSingleIntervalSeedsBothSplitIntervals() throws {
        let defaults = try makeDefaults()
        defaults.set(25.0, forKey: SettingsStore.refreshIntervalDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.refreshIntervalOnBatterySeconds, 25, accuracy: 0.001)
        XCTAssertEqual(settings.refreshIntervalOnPowerSeconds, 25, accuracy: 0.001)
    }

    func testOutOfRangeOldIntervalIsClampedDuringMigration() throws {
        let defaults = try makeDefaults()
        defaults.set(500.0, forKey: SettingsStore.refreshIntervalDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.refreshIntervalOnBatterySeconds, 60, accuracy: 0.001)
        XCTAssertEqual(settings.refreshIntervalOnPowerSeconds, 60, accuracy: 0.001)
    }

    func testOldIntervalOffTheBatteryGridSnapsToTheNearestStep() throws {
        // The old slider stored multiples of 5; 10 is not on the 5, 7, 9 … grid.
        let defaults = try makeDefaults()
        defaults.set(10.0, forKey: SettingsStore.refreshIntervalDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.refreshIntervalOnBatterySeconds, 11, accuracy: 0.001)
        XCTAssertEqual(settings.refreshIntervalOnPowerSeconds, 10, accuracy: 0.001)
    }

    func testFreshInstallUsesTheSplitDefaults() throws {
        let settings = SettingsStore(defaults: try makeDefaults())
        XCTAssertEqual(settings.refreshIntervalOnBatterySeconds, 15, accuracy: 0.001)
        XCTAssertEqual(settings.refreshIntervalOnPowerSeconds, 5, accuracy: 0.001)
    }

    func testStoredSplitIntervalsWinOverTheOldKey() throws {
        let defaults = try makeDefaults()
        defaults.set(30.0, forKey: SettingsStore.refreshIntervalDefaultsKey)
        defaults.set(45.0, forKey: SettingsStore.refreshIntervalOnBatteryDefaultsKey)
        defaults.set(10.0, forKey: SettingsStore.refreshIntervalOnPowerDefaultsKey)
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.refreshIntervalOnBatterySeconds, 45, accuracy: 0.001)
        XCTAssertEqual(settings.refreshIntervalOnPowerSeconds, 10, accuracy: 0.001)
    }

    func testOnPowerIntervalMirrorsToTheOldKeyForOlderBuilds() throws {
        let defaults = try makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.refreshIntervalOnPowerSeconds = 40
        settings.refreshIntervalOnBatterySeconds = 55
        XCTAssertEqual(defaults.double(forKey: SettingsStore.refreshIntervalDefaultsKey), 40, accuracy: 0.001)
    }

    // MARK: Selection

    func testPowerSourceSelection() throws {
        XCTAssertFalse(SettingsStore.usesPowerRefreshInterval(onBattery))
        XCTAssertTrue(SettingsStore.usesPowerRefreshInterval(pluggedIn))
        XCTAssertTrue(SettingsStore.usesPowerRefreshInterval(noBattery))

        let settings = SettingsStore(defaults: try makeDefaults())
        settings.refreshIntervalOnBatterySeconds = 60
        settings.refreshIntervalOnPowerSeconds = 10
        XCTAssertEqual(settings.refreshInterval(for: onBattery), .seconds(60))
        XCTAssertEqual(settings.refreshInterval(for: pluggedIn), .seconds(10))
        XCTAssertEqual(settings.refreshInterval(for: noBattery), .seconds(10))
    }

    func testPublisherFollowsPlugAndUnplugAndSettingChanges() throws {
        let settings = SettingsStore(defaults: try makeDefaults())
        settings.refreshIntervalOnBatterySeconds = 60
        settings.refreshIntervalOnPowerSeconds = 10
        let battery = CurrentValueSubject<BatteryStatus, Never>(onBattery)
        var received: [Duration] = []
        let cancellable = settings
            .refreshIntervalPublisher(battery: battery.eraseToAnyPublisher())
            .sink { received.append($0) }

        battery.send(pluggedIn)
        // A battery reading that does not change the power source repeats nothing.
        battery.send(BatteryStatus(rawPercentage: 61, isPresent: true, isCharging: true,
                                   isLowPowerMode: false, isConnectedToPower: true))
        battery.send(onBattery)
        settings.refreshIntervalOnBatterySeconds = 31
        // Changing the inactive interval leaves the active one alone.
        settings.refreshIntervalOnPowerSeconds = 20
        cancellable.cancel()

        XCTAssertEqual(received, [.seconds(60), .seconds(10), .seconds(60), .seconds(31)])
    }
}
