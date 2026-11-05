import SwiftUI

/// QWeather account, location mode and city for the panel's Weather section.
/// Shown on the Panel page while the Weather section is enabled.
struct WeatherSettingsGroup: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    /// Injected for tests; the app uses the login Keychain and QWeather.
    var keyStore: WeatherAPIKeyStoring = KeychainWeatherAPIKeyStore()
    var client: WeatherForecastFetching = QWeatherClient()

    @State private var apiKey = ""
    @State private var savedKey = ""
    @State private var cityQuery = ""
    @State private var results: [QWeatherCity] = []
    @State private var searchMessage: String?
    @State private var isSearching = false

    var body: some View {
        SettingsGroup(
            localization.string(.settingsWeatherGroup),
            footnote: localization.string(.settingsWeatherDescription)
        ) {
            SettingsRow("server.rack", tint: .teal, title: localization.string(.settingsWeatherAPIHost)) {
                TextField("abcxyz.qweatherapi.com", text: $store.weatherAPIHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
                    .labelsHidden()
                    .accessibilityLabel(localization.string(.settingsWeatherAPIHost))
            }

            SettingsDivider()

            SettingsRow(
                "key",
                tint: .orange,
                title: localization.string(.settingsWeatherAPIKey),
                subtitle: !savedKey.isEmpty && apiKey == savedKey
                    ? localization.string(.settingsWeatherSaved)
                    : nil
            ) {
                HStack(spacing: 6) {
                    SecureField(localization.string(.settingsWeatherAPIKey), text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .labelsHidden()
                    Button(localization.string(.settingsWeatherSave)) { saveKey() }
                        .controlSize(.small)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == savedKey)
                }
            }

            SettingsDivider()

            SettingsMenuRow(
                symbol: "location",
                tint: .blue,
                title: localization.string(.settingsWeatherLocationMode),
                subtitle: localization.string(.settingsWeatherLocationDescription),
                selection: $store.weatherLocationMode,
                options: WeatherLocationMode.allCases,
                label: modeLabel
            )

            SettingsDivider()

            SettingsRow(
                "building.2",
                tint: .indigo,
                title: localization.string(.settingsWeatherCity),
                subtitle: cityDescription
            ) {
                HStack(spacing: 6) {
                    TextField(localization.string(.settingsWeatherCityPlaceholder), text: $cityQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                        .labelsHidden()
                        .onSubmit { search() }
                    Button(localization.string(.settingsWeatherCitySearch)) { search() }
                        .controlSize(.small)
                        .disabled(isSearching || cityQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            ForEach(results) { city in
                SettingsDivider()
                Button {
                    store.weatherManualLocation = city.location
                    results = []
                    cityQuery = ""
                    searchMessage = nil
                } label: {
                    HStack {
                        Text(city.name)
                        Text(city.region).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            savedKey = keyStore.readKey()
            apiKey = savedKey
        }
    }

    private var cityDescription: String {
        if let searchMessage { return searchMessage }
        return store.weatherManualLocation?.name ?? localization.string(.settingsWeatherCityNone)
    }

    private func modeLabel(_ mode: WeatherLocationMode) -> String {
        switch mode {
        case .automatic: localization.string(.settingsWeatherLocationAutomatic)
        case .manual: localization.string(.settingsWeatherLocationManual)
        }
    }

    private func saveKey() {
        keyStore.writeKey(apiKey)
        savedKey = keyStore.readKey()
        apiKey = savedKey
        store.weatherCredentialRevision &+= 1
    }

    private func search() {
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearching else { return }
        let credentials = QWeatherCredentials(host: store.weatherAPIHost, apiKey: keyStore.readKey())
        let language = QWeatherLanguage.code(for: localization.resolvedLanguage)
        isSearching = true
        searchMessage = nil
        Task { @MainActor in
            defer { isSearching = false }
            do {
                let found = try await client.lookupCities(named: query, credentials: credentials, language: language)
                results = found
                if found.isEmpty { searchMessage = localization.string(.settingsWeatherCityNoResults) }
            } catch let failure as WeatherFailure {
                results = []
                searchMessage = localization.string(WeatherPanelMapper.failureKey(failure))
            } catch {
                results = []
                searchMessage = localization.string(.weatherUnavailable)
            }
        }
    }
}
