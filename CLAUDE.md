# CLAUDE.md

Guidance for Claude Code (and other AI assistants) working in this repository.

## What this is

A native **SwiftUI macOS app** that is a companion/remote-control client for the
ESP32 firmware project
[BandPassFilterController](https://github.com/VU3ESV/BandPassFilterController)
(an SO2R / TCI contest band-pass-filter switcher).

The app does **not** talk to radios or relays directly. It is a thin client over
the firmware's existing **HTTP web-portal API** — it polls the device for status
and POSTs configuration/commands, replicating the device's web UI as a native Mac
window. The firmware is the source of truth; this app must follow its API exactly.

## Build / run / deploy

Requirements: macOS 13+, Swift 5.9+ toolchain (Xcode command-line tools).

```bash
swift build                 # debug build
swift test                  # unit tests (Tests/BandPassFilterControllerTests, no device needed)
swift run                   # build + launch the app
./build-app.sh              # release build -> ./dist/Band Pass Filter Controller.app
open "dist/Band Pass Filter Controller.app"
```

- `build-app.sh` wraps the SPM release binary into a `.app` bundle using
  `Resources/Info.plist` and ad-hoc code-signs it.
- There is no Xcode project; open `Package.swift` in Xcode if you prefer the IDE.
- This is a Swift Package (`.executableTarget`), not an `xcodegen`/`.xcodeproj` setup.

## Architecture

```
Sources/BandPassFilterController/
├── App.swift                          # @main App scene (single WindowGroup)
├── Models/
│   ├── Band.swift                     # Yaesu BCD band enum + tolerant parsing
│   ├── DeviceStatus.swift             # /status JSON model (DeviceStatus, RadioStatus)
│   ├── DeviceConfig.swift             # editable config + /save form encoding
│   └── DeviceIdentity.swift           # /discover JSON (incl. auth_required)
├── Networking/
│   ├── BPFClient.swift                # async URLSession client over the HTTP API (+ typed 401 errors)
│   ├── DeviceAuth.swift               # Digest/Basic challenge policy + per-request URLSession delegate
│   ├── DeviceKeychain.swift           # admin password in the login Keychain (per device hostname)
│   └── DiscoveryService.swift         # Bonjour browse of _bpf-so2r._tcp (mDNS auto-discovery)
├── ViewModels/
│   └── ControllerViewModel.swift      # @MainActor ObservableObject: polling, state, actions
└── Views/
    ├── ContentView.swift              # NavigationSplitView + sidebar + connection badge
    ├── DashboardView.swift            # filter cards (band/freq/RF sensors) + device info (+firmware)
    ├── ControlsView.swift             # manual bypass
    ├── HistoryView.swift              # band-change history + clear
    └── SettingsView.swift             # TCI servers, device password, network, backup/restore, web pages, reboot/factory reset
Tests/BandPassFilterControllerTests/   # XCTest: pure logic only (no device, no Keychain)
```

Data flow: `ControllerViewModel` owns a `BPFClient`, runs a polling `Task` that
calls `GET /status` every `pollInterval` seconds, and publishes a `DeviceStatus`
the views render. User actions (save/bypass/reboot/reset) call client methods then
refresh. The device address and poll settings persist via `@AppStorage`.

## The device API (authoritative — verified against firmware source)

These field names come from the firmware, **not** from its docs (the published
docs had several wrong names). When in doubt, read the firmware, not the README.
The firmware lives locally at `../BandPassFilterController` (a sibling clone) —
specifically `ESP32_SO2R_TCI/WebPortal.h`, `ESP32_SO2R_TCI.ino` (`statusJson()`),
and `ESP32_SO2R_TCI/BcdBandPlan.h` (`bandName()`).

| Route | Method | Params / Body | Notes |
|-------|--------|---------------|-------|
| `/discover` | GET | — | static identity JSON: `service, vendor, product, version, build, hostname, ip, bpf_count, ports, endpoints`, and (v0.6.0+) `auth_required`. Companion to the `_bpf-so2r._tcp` mDNS service. |
| `/status` | GET | — | JSON (below); now includes `version`, `build`, `sensors`, `history` |
| `/config` | GET | — | JSON config (host/port/iaru/ssid/hostname); used by Settings + backup. No password. |
| `/save` | POST | `ssid, pass, hostname, r1_host, r1_port, r1_iaru, r2_host, r2_port, r2_iaru` (+ optional `admin_pass`, v0.6.0) | form-urlencoded; app never sends `admin_pass` |
| `/bypass` | POST | `bpf=1\|2 & on=0\|1` | manual bypass |
| `/history` | POST | `clear=YES` | clears the band-change history ring buffer |
| `/reboot` | POST | — | soft restart |
| `/factory_reset` | POST | `confirm=YES` | wipes EEPROM |
| `/live` | GET | — | device-rendered live HTML page (app just opens it in a browser) |

`/status` JSON shape (firmware ≥ v0.5.0):
```json
{
  "filter": "<label>",
  "version": "0.5.0",             // firmware version
  "build": "<__DATE__ __TIME__>", // firmware build stamp
  "mode": "shared" | "dual",
  "ap_mode": true|false,
  "wifi": "up" | "down",          // STRING, not bool
  "ip": "192.168.x.x",
  "rssi": -57,
  "r1": { "connected": bool, "freq_hz": int, "band": "20m"|"bypass"|..., "tuning": bool },
  "r2": { ...same... },
  "sensors": { "bpf1_fwd_mv": int, "bpf1_rev_mv": int, "bpf2_fwd_mv": int, "bpf2_rev_mv": int },
  "history": [ { "t": uptime_s, "bpf": 1|2, "hz": int, "code": int, "inh": bool, "tune": bool } ],
  "history_count": int,
  "uptime_s": int
}
```

Gotchas already handled in the models — preserve these:
- `wifi` is the string `"up"`/`"down"` (see `DeviceStatus.wifiState` / `wifiUp`).
- `band` is a string label from `bandName()` (`"160m"`…`"6m"`, or `"bypass"`).
  `Band.resolve` parses both string labels and numeric BCD codes (1–10) tolerantly.
- `/save` IARU fields are only accepted by the firmware when `1...3`; `0` means
  "leave unchanged", so `DeviceConfig.formBody()` omits `r{n}_iaru` when 0.
- In **shared** mode the firmware drives both BPFs from one TCI client; `r2`
  mirrors `r1`. The dashboard/controls fall back to `r1` for BPF 2 when shared.
- `sensors` are raw RF-detector millivolts (0 = no RF / no detector). We show
  them verbatim and deliberately do **not** derive SWR — the detectors are
  uncalibrated and the idle floor reads fwd≈rev, which would fake a huge SWR.
- `history` arrives oldest-first; the History view reverses it for newest-first.
  Event `t` is the device uptime at the event; the UI shows it relative to the
  current `uptime_s` ("3m ago").
- Backup = `GET /config` saved to a `.json` file; restore decodes that file into
  `DeviceConfig` (already `Decodable`) for review, then the user taps Save.
- OTA (firmware ≥ #3) is ArduinoOTA/espota only — **no web endpoint**, so the app
  can't trigger updates; it only surfaces the running `version`/`build`.
- Discovery (firmware ≥ #6) has two halves: the device advertises mDNS
  `_bpf-so2r._tcp` (TXT: vendor/product/version/build/host/bpf/path/ws_live) and
  serves `GET /discover`. `DiscoveryService` browses the mDNS service with
  `NetServiceBrowser`; `BPFClient.fetchDiscover()` reads `/discover` to confirm a
  device's identity. The Settings screen lists discovered devices; picking one
  calls `ViewModel.use(device)` (sets host → reconnect → reload config).
- `DiscoveryService` is a plain `ObservableObject` (NOT `@MainActor`): its
  `NetServiceBrowser` delegate callbacks already run on the main run loop (the
  thread that called `start()`), and `MainActor.assumeIsolated` is macOS-14-only.
- `Info.plist` must keep `NSBonjourServices` (`_bpf-so2r._tcp`) and
  `NSLocalNetworkUsageDescription`, or the OS blocks the Bonjour browse.
- Auth (firmware ≥ v0.6.0): with an admin password set, `GET /` and every POST
  (`/save`, `/bypass`, `/history`, `/reboot`, `/factory_reset`) answer 401 +
  `WWW-Authenticate: Digest realm="BandPassFilterController"` (ESP32
  `requestAuthentication(DIGEST_AUTH, …)`), user `admin`. `/status`, `/config`,
  `/discover`, `/live` and the `:81` WebSocket stay open. `BPFClient` builds one
  ephemeral session per request with a `DeviceAuthDelegate` and invalidates it
  after. The ESP32 keeps one nonce and regenerates it on every challenge, so a
  fresh 401 is normal and is answered again; only `previousFailureCount > 0`
  means the password was rejected (`DeviceAuth.decide`). 401 maps to
  `BPFClientError.passwordRequired` / `.passwordRejected`.
- The password lives in the login Keychain: generic password, service
  `BandPassFilterController`, account = the hostname the **device** reports
  (`/discover`, else fetched `/config`) — never the editable draft. The view model
  loads it when that hostname becomes known, so a Keychain prompt appears at
  connect time rather than mid-bypass.
- Bypass is safety-relevant (pressed before tuning an ATU at high power). The UI
  shows bypass only from `/status` (`tuning` is true while manual bypass is on),
  never optimistically; a failed `/bypass` beeps, raises an alert and keeps a red
  banner on Controls until a later bypass succeeds. `reboot()` / `factoryReset()`
  tolerate the dropped connection but rethrow auth failures.

## Conventions

- Pure SwiftUI, no third-party dependencies; keep it that way unless necessary.
- Networking is `async`/`await` on `URLSession`; all UI state is `@MainActor`.
- Decoders are deliberately tolerant (`try?` + defaults) so a firmware field
  rename degrades gracefully instead of blanking the whole dashboard.
- Target floor is macOS 13 — avoid macOS 14+ only APIs (e.g. `.background.secondary`).

## When changing the API surface

If you touch request/response handling, cross-check the firmware in
`../BandPassFilterController` first. A mismatch here silently shows stale or empty
data rather than erroring, so verify field names against the C++ source.
