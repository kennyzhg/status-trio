import Foundation

enum PopupSection: String, CaseIterable, Identifiable, Sendable {
    case battery
    case quickActions
    case network
    case vpn
    case bluetooth
    case volume
    case brightness
    case audioInput
    case inputSource
    case hardwareMonitor
    /// Three-day QWeather forecast. Off by default; it needs an API key.
    case weather

    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .battery: .settingsPopupOrderBattery
        case .quickActions: .settingsPopupOrderQuickActions
        case .network: .settingsPopupOrderNetwork
        case .vpn: .vpnTitle
        case .bluetooth: .bluetoothTitle
        case .volume: .settingsPopupOrderVolume
        case .brightness: .settingsPopupOrderBrightness
        case .audioInput: .settingsPopupOrderAudioInput
        case .inputSource: .settingsPopupOrderInputSource
        case .hardwareMonitor: .hardwareMonitorTitle
        case .weather: .settingsPopupOrderWeather
        }
    }

    var systemImage: String {
        switch self {
        case .battery: SymbolFallback.name("battery.100percent", "battery.100")
        case .quickActions: "moon.zzz"
        case .network: "wifi"
        case .vpn: "lock.shield"
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .volume: "speaker.wave.2"
        case .brightness: SymbolFallback.name("sun.max", "sun.max")
        case .audioInput: "mic"
        case .inputSource: "keyboard"
        case .hardwareMonitor: "cpu"
        case .weather: "cloud.sun"
        }
    }
}
