# Weather section (QWeather)

An optional status-panel section shows a three-day forecast (today, tomorrow
and the day after) with a high/low temperature trend. It is **off by default**
and has no effect until it is enabled in **Settings › Panel** and configured.

## Data source

[QWeather](https://dev.qweather.com/) (和风天气). Each user brings their own
project: the console provides an account-specific **API Host** and an **API
Key**. The host is stored in UserDefaults (`weatherAPIHost`); the key is stored
in the login Keychain (service `<bundle id>.weather`, account `QWeatherAPIKey`)
and is sent only in the `X-QW-Api-Key` header, never in a URL.

Endpoints: `GET /v7/weather/3d?location=<lon>,<lat>&lang=<lang>&unit=m` and
`GET /geo/v2/city/lookup?location=<name or lon,lat>&number=5`.

## Location

- **Automatic** (default): a one-shot, kilometre-accuracy Core Location fix,
  only when the app already holds location access (it asks for it for the
  Wi-Fi name). Weather never prompts on its own. The fix's name comes from the
  city lookup and is cached per rounded coordinate.
- Without access, or if the fix fails or times out (10 s), the city chosen in
  Settings is used. **City only** skips location entirely.
- Coordinates are rounded to 0.01° (about 1 km) before they leave the Mac.

## Lifecycle and cost

- No timer and no background work. Opening the panel with the section visible
  is the only trigger; a forecast younger than 30 minutes for the same host,
  key, mode, city and language is reused. The refresh button forces a fetch.
- `WeatherController` is created on first use, so a panel that never shows the
  section never creates a Keychain reader, a location manager or a client.
- A failure keeps the last forecast visible under a short status line.

## Verification status

- Unit coverage: `QWeatherClientTests`, `WeatherControllerTests`,
  `WeatherPanelMapperTests`.
- **NOT RUN**: a live request against a real QWeather account, the Core
  Location fix on hardware, and a visual check of the section.
