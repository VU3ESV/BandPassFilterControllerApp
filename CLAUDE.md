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
│   └── DeviceConfig.swift             # editable config + /save form encoding
├── Networking/
│   └── BPFClient.swift                # async URLSession client over the HTTP API
├── ViewModels/
│   └── ControllerViewModel.swift      # @MainActor ObservableObject: polling, state, actions
└── Views/
    ├── ContentView.swift              # NavigationSplitView + sidebar + connection badge
    ├── DashboardView.swift            # filter cards + device info
    ├── ControlsView.swift             # manual bypass + reboot + factory reset
    └── SettingsView.swift             # app connection + TCI servers + device network
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
| `/status` | GET | — | JSON (below) |
| `/save` | POST | `ssid, pass, hostname, r1_host, r1_port, r1_iaru, r2_host, r2_port, r2_iaru` | form-urlencoded |
| `/bypass` | POST | `bpf=1\|2 & on=0\|1` | manual bypass |
| `/reboot` | POST | — | soft restart |
| `/factory_reset` | POST | `confirm=YES` | wipes EEPROM |

`/status` JSON shape:
```json
{
  "filter": "<label>",
  "mode": "shared" | "dual",
  "ap_mode": true|false,
  "wifi": "up" | "down",          // STRING, not bool
  "ip": "192.168.x.x",
  "rssi": -57,
  "r1": { "connected": bool, "freq_hz": int, "band": "20m"|"bypass"|..., "tuning": bool },
  "r2": { ...same... },
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
