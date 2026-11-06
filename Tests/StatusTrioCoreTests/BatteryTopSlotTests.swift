import Foundation
import XCTest
@testable import StatusTrioCore

/// Issue #274: the ring's top slot follows the hardware, can be hidden, or can
/// carry whole-machine watts instead of the battery status.
@MainActor
final class BatteryTopSlotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private let laptop = BatteryStatus(rawPercentage: 68, isPresent: true, isCharging: false,
                                       isLowPowerMode: false, isConnectedToPower: false)
    private let chargingLaptop = BatteryStatus(rawPercentage: 40, isPresent: true, isCharging: true,
                                               isLowPowerMode: false, isConnectedToPower: true)
    private let desktop = BatteryStatus(rawPercentage: 100, isPresent: false, isCharging: false,
                                        isLowPowerMode: false, isConnectedToPower: true)

    private func makeDefaults() throws -> UserDefaults {
        let suite = "BatteryTopSlotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        return defaults
    }

    private func ring(
        _ battery: BatteryStatus,
        topSlot: BatteryTopSlotContent,
        center: ConnectionCenterSource = .network,
        power: SystemPowerSample? = nil
    ) -> OuterRingState? {
        IconPresentationMapper.scene(
            inputs: IconPresentationInputs(
                snapshot: StatusSnapshot(battery: battery, wifi: .placeholder, volume: .placeholder),
                audioIcon: nil,
                systemPower: power
            ),
            configuration: IconPresentationConfiguration(
                battery: BatteryIconOptions(topSlotContent: topSlot),
                connection: ConnectionIconOptions(centerSource: center),
                volume: .standard,
                bluetooth: .standard
            ),
            now: now
        ).outerRing
    }

    private func text(_ ring: OuterRingState?) -> String? {
        guard case .text(let state) = ring?.accessory else { return nil }
        return state.text
    }

    // MARK: Resolution

    func testAutomaticFollowsRuntimeBatteryPresence() {
        XCTAssertEqual(BatteryTopSlotContent.automatic.resolved(for: laptop), .battery)
        XCTAssertEqual(BatteryTopSlotContent.automatic.resolved(for: desktop), .hidden)
        for explicit in [BatteryTopSlotContent.battery, .hidden, .power] {
            for battery in [laptop, chargingLaptop, desktop] {
                XCTAssertEqual(explicit.resolved(for: battery), explicit)
            }
        }
    }

    func testPowerWhenPluggedInFollowsTheAdapter() {
        XCTAssertEqual(BatteryTopSlotContent.powerWhenPluggedIn.resolved(for: laptop), .battery)
        XCTAssertEqual(BatteryTopSlotContent.powerWhenPluggedIn.resolved(for: chargingLaptop), .power)
        XCTAssertEqual(BatteryTopSlotContent.powerWhenPluggedIn.resolved(for: desktop), .power)
    }

    func testOnlyAResolvedPowerSlotKeepsTheSamplerAlive() {
        for battery in [laptop, chargingLaptop, desktop] {
            XCTAssertTrue(BatteryTopSlotContent.power.needsPowerSampling(for: battery))
            for content in [BatteryTopSlotContent.automatic, .battery, .hidden] {
                XCTAssertFalse(content.needsPowerSampling(for: battery), "\(content)")
            }
        }
        // The adaptive choice releases the sampler on battery.
        XCTAssertFalse(BatteryTopSlotContent.powerWhenPluggedIn.needsPowerSampling(for: laptop))
        XCTAssertTrue(BatteryTopSlotContent.powerWhenPluggedIn.needsPowerSampling(for: chargingLaptop))
        XCTAssertTrue(BatteryTopSlotContent.powerWhenPluggedIn.needsPowerSampling(for: desktop))
    }

    func testPowerWhenPluggedInMapsWattsOnPowerAndPercentOnBattery() {
        let sample = SystemPowerSample(watts: 31.2, readAt: now)
        XCTAssertEqual(text(ring(chargingLaptop, topSlot: .powerWhenPluggedIn, power: sample)), "31")
        XCTAssertEqual(text(ring(desktop, topSlot: .powerWhenPluggedIn, power: sample)), "31")
        // A desktop shows its watts on the empty track (upstream 1.9.4).
        XCTAssertEqual(ring(desktop, topSlot: .powerWhenPluggedIn, power: sample)?.segments.first?.progress, 0)
        // On battery it is the battery gap, even with a sample lying around.
        XCTAssertEqual(ring(laptop, topSlot: .powerWhenPluggedIn, power: sample),
                       ring(laptop, topSlot: .battery))
        XCTAssertEqual(text(ring(laptop, topSlot: .powerWhenPluggedIn, power: sample)), "68")
        // Plugged in with no fresh reading: the battery status, never a fake 0.
        XCTAssertEqual(ring(chargingLaptop, topSlot: .powerWhenPluggedIn, power: nil),
                       ring(chargingLaptop, topSlot: .battery))
    }

    // MARK: Mapper

    func testAutomaticKeepsTheLaptopPercentage() {
        let ring = ring(laptop, topSlot: .automatic)
        XCTAssertEqual(ring?.gap, .value)
        XCTAssertEqual(text(ring), "68")
        XCTAssertEqual(ring, self.ring(laptop, topSlot: .battery))
    }

    func testAutomaticHidesTheSlotOnAMacWithoutABattery() {
        let ring = ring(desktop, topSlot: .automatic)
        XCTAssertEqual(ring?.gap, .closed)
        XCTAssertNil(ring?.accessory)
        // Upstream 1.9.4: the ring stays as an empty track, not a full circle.
        XCTAssertEqual(ring?.segments.first?.progress, 0)
    }

    func testExplicitBatteryOnADesktopNoLongerInventsOneHundred() {
        // Upstream 1.9.4 dropped the placeholder 100 for a Mac with no battery.
        let ring = ring(desktop, topSlot: .battery)
        XCTAssertEqual(ring?.gap, .closed)
        XCTAssertNil(ring?.accessory)
        XCTAssertEqual(ring?.segments.first?.progress, 0)
    }

    func testHiddenClosesTheGapAndKeepsTheLaptopLevel() {
        let ring = ring(chargingLaptop, topSlot: .hidden)
        XCTAssertEqual(ring?.gap, .closed)
        XCTAssertNil(ring?.accessory)
        XCTAssertEqual(ring?.segments.first?.progress ?? 0, 0.4, accuracy: 0.0001)
        // Nothing in the gap to pulse.
        XCTAssertEqual(ring?.effect?.pulsesAccessory, false)
    }

    func testPowerShowsFreshIntegerWatts() {
        let sample = SystemPowerSample(watts: 12.6, readAt: now)
        for battery in [laptop, desktop, chargingLaptop] {
            let ring = ring(battery, topSlot: .power, power: sample)
            XCTAssertEqual(ring?.gap, .value)
            XCTAssertEqual(text(ring), "13")
            XCTAssertEqual(ring?.effect?.pulsesAccessory ?? false, false)
        }
    }

    func testPowerIsClampedToThreeDigits() {
        let ring = ring(desktop, topSlot: .power, power: SystemPowerSample(watts: 4_000, readAt: now))
        XCTAssertEqual(text(ring), "999")
    }

    func testStalePowerFallsBackHonestly() {
        let stale = SystemPowerSample(watts: 20, readAt: now.addingTimeInterval(-600))
        // A laptop keeps its battery status rather than a stale value.
        XCTAssertEqual(ring(laptop, topSlot: .power, power: stale),
                       ring(laptop, topSlot: .battery))
        // A desktop never invents a percentage or a zero.
        XCTAssertEqual(text(ring(desktop, topSlot: .power, power: stale)), "--")
        XCTAssertEqual(text(ring(desktop, topSlot: .power, power: nil)), "--")
    }

    func testChargingStatusCentreDoesNotSwallowAReplacedTopSlot() {
        let sample = SystemPowerSample(watts: 8, readAt: now)
        let ring = ring(laptop, topSlot: .power, center: .chargingStatus, power: sample)
        XCTAssertEqual(ring?.gap, .value)
        XCTAssertEqual(text(ring), "8")
        // With the battery slot the charging-status centre still closes the gap.
        XCTAssertEqual(self.ring(laptop, topSlot: .battery, center: .chargingStatus)?.gap, .closed)
    }

    // MARK: Settings

    func testFreshInstallIsAutomaticAndChoicesPersist() throws {
        let defaults = try makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.batteryTopSlotContent, .automatic)
        XCTAssertEqual(settings.batteryIconOptions.topSlotContent, .automatic)

        settings.batteryTopSlotContent = .power
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.batteryTopSlotContent, .power)
        XCTAssertEqual(reloaded.batteryIconOptions.topSlotContent, .power)
    }

    func testUnknownStoredValueDecodesAsAutomatic() throws {
        let defaults = try makeDefaults()
        defaults.set("somethingElse", forKey: SettingsStore.batteryTopSlotContentDefaultsKey)
        XCTAssertEqual(SettingsStore(defaults: defaults).batteryTopSlotContent, .automatic)
    }

    func testIconAppearancePublisherCarriesTheChoice() throws {
        let settings = SettingsStore(defaults: try makeDefaults())
        var received: [BatteryTopSlotContent] = []
        let cancellable = settings.iconAppearancePublisher
            .sink { received.append($0.batteryOptions.topSlotContent) }
        settings.batteryTopSlotContent = .hidden
        cancellable.cancel()
        XCTAssertEqual(received.first, .automatic)
        XCTAssertEqual(received.last, .hidden)
    }
}
