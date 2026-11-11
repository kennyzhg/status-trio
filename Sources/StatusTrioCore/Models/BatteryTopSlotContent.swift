import Foundation

/// What the top slot of the battery ring (its top gap) shows (#274).
///
/// The ring sits on every Mac, but a Mac with no internal battery — a Mac mini,
/// Mac Studio, Mac Pro or iMac — has no level to put in the gap: it used to
/// show a placeholder `100` that carries no information. This choice lets the
/// slot follow the hardware, be hidden, or carry another live value.
///
/// Battery presence is decided at runtime from the IOKit snapshot
/// (`BatteryStatus.isPresent`), never from a list of models.
enum BatteryTopSlotContent: String, CaseIterable, Identifiable, Sendable {
    /// Follow the per-state top markers (#315), including the battery-less
    /// marker that upstream now offers (plug / bolt / hidden).
    case automatic
    /// Always the battery status (the pre-#274 behaviour).
    case battery
    /// Never anything: the top gap closes into an unbroken ring.
    case hidden
    /// Fresh whole-machine watts from the shared power sampler.
    case power
    /// Watts while connected to power, the battery status while on battery.
    /// A Mac with no battery is always on power, so it always shows watts.
    case powerWhenPluggedIn

    var id: Self { self }

    /// The concrete content for the current battery reading: `.automatic` and
    /// `.powerWhenPluggedIn` follow the hardware and the adapter at runtime.
    func resolved(for battery: BatteryStatus) -> Self {
        switch self {
        case .automatic:
            return .battery
        case .powerWhenPluggedIn:
            return Self.isOnPower(battery) ? .power : .battery
        case .battery, .hidden, .power:
            return self
        }
    }

    /// Whether the current reading needs periodic power reads. The adaptive
    /// choice releases the sampler while the Mac runs on battery.
    func needsPowerSampling(for battery: BatteryStatus) -> Bool {
        resolved(for: battery) == .power
    }

    static func isOnPower(_ battery: BatteryStatus) -> Bool {
        !battery.isPresent || battery.isConnectedToPower
    }
}
