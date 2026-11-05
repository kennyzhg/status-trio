import Foundation
import XCTest
@testable import StatusTrioCore

/// Issue #262: the "always start on the summary page" switch is opt-in and
/// persists, so upgrading users keep the remembered detail page (8701bb57).
@MainActor
final class ReturnsToSummaryOnOpenSettingTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "ReturnsToSummaryOnOpenSettingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return defaults
    }

    func testDefaultsToOffForFreshAndUpgradingUsers() throws {
        let defaults = try makeDefaults()
        // An upgrading user has other keys but never this one.
        defaults.set(true, forKey: SettingsStore.showsBatteryPercentageDefaultsKey)
        XCTAssertFalse(SettingsStore(defaults: defaults).returnsToSummaryOnOpen)
        XCTAssertNil(defaults.object(forKey: SettingsStore.returnsToSummaryOnOpenDefaultsKey))
    }

    func testChoicePersistsBothWays() throws {
        let defaults = try makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.returnsToSummaryOnOpen = true
        XCTAssertTrue(SettingsStore(defaults: defaults).returnsToSummaryOnOpen)
        settings.returnsToSummaryOnOpen = false
        XCTAssertFalse(SettingsStore(defaults: defaults).returnsToSummaryOnOpen)
    }
}
