import Foundation
import Security

/// Holds the QWeather API key. The key is a secret, so it lives in the login
/// Keychain rather than in UserDefaults next to ordinary preferences.
protocol WeatherAPIKeyStoring: AnyObject {
    func readKey() -> String
    func writeKey(_ key: String)
}

final class KeychainWeatherAPIKeyStore: WeatherAPIKeyStoring {
    private let service: String
    private let account = "QWeatherAPIKey"

    init(service: String = (Bundle.main.bundleIdentifier ?? "com.lingsmbp.StatusTrio") + ".weather") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func readKey() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return ""
        }
        return key
    }

    func writeKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

/// In-memory store for tests and previews.
final class InMemoryWeatherAPIKeyStore: WeatherAPIKeyStoring {
    private var key: String
    init(key: String = "") { self.key = key }
    func readKey() -> String { key }
    func writeKey(_ key: String) { self.key = key.trimmingCharacters(in: .whitespacesAndNewlines) }
}
