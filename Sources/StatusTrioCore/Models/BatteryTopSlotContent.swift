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
    /// The battery status on a Mac with a battery; hidden on one without.
    case automatic
    /// Always the battery status (the pre-#274 behaviour).
    case battery
    /// Never anything: the top gap closes into an unbroken ring.
    case hidden
    /// Fresh whole-machine watts from the shared power sampler.
    case power

    var id: Self { self }

    /// The concrete content once `.automatic` has been decided for this Mac.
    func resolved(hasBattery: Bool) -> Self {
        guard self == .automatic else { return self }
        return hasBattery ? .battery : .hidden
    }

    /// Only an explicit power choice asks for periodic power reads;
    /// `.automatic` never resolves to `.power`.
    var needsPowerSampling: Bool { self == .power }
}
