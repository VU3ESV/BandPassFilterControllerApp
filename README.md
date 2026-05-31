# Band Pass Filter Controller — macOS App

A native **SwiftUI** macOS companion for the ESP32
[BandPassFilterController](https://github.com/VU3ESV/BandPassFilterController)
(SO2R / TCI band-pass filter switcher).

It mirrors everything the device's built-in web portal does — live filter state,
TCI connection status, and full configuration — in a native Mac window, polling
the device's HTTP API instead of you opening a browser.

## Features

- **Dashboard** — a live card per band-pass filter (BPF 1 / BPF 2) showing the
  selected band (Yaesu BCD code), VFO frequency, RX / TUNE / bypass state, the
  per-radio TCI link, and the **RF forward/reverse detector readings** (mV).
  Plus device **firmware version/build**, Wi-Fi / IP / RSSI / mode / uptime.
- **Controls** — manual bypass ON/OFF for each filter (for radios like AetherSDR
  whose TCI server doesn't emit tune events).
- **History** — the device's recent **band-change events** (newest first, with
  relative timestamps, ATU-tune and bypass flags), and a button to clear it.
- **Settings** — configure the two TCI servers (host : port : IARU region), the
  device Wi-Fi credentials, and the mDNS hostname, then push them to the device —
  exactly like the web `Save` button. Also: **back up / restore** the config to a
  JSON file, open the device's **web portal / live page** in a browser, and
  **reboot / factory reset** the controller. Plus the app's own address/poll rate.

On first load (and whenever you change the address) Settings reads the device's
real stored config via `GET /config` and pre-fills the form. The app polls
`GET /status` on an interval (default 1.5 s) and shows a connection badge; all
writes use the same routes as the firmware web portal.

> **Firmware updates (OTA):** the firmware updates over Wi-Fi via ArduinoOTA
> (`espota`), which has no HTTP endpoint — so the app can't push updates. It does
> surface the running version/build so you know what's installed.

## Device API used (firmware ≥ v0.5.0)

| Route | Method | Purpose |
|-------|--------|---------|
| `/status` | GET | JSON: `version`, `build`, `mode`, `ap_mode`, `wifi`, `ip`, `rssi`, `r1`/`r2` `{connected, freq_hz, band, tuning}`, `sensors`, `history`, `uptime_s` |
| `/config` | GET | JSON stored config (pre-fill Settings + backup); never includes the Wi-Fi password |
| `/save` | POST | form: `ssid`, `pass`, `hostname`, `r{1,2}_host`, `r{1,2}_port`, `r{1,2}_iaru` |
| `/bypass` | POST | `bpf=1\|2 & on=0\|1` |
| `/history` | POST | `clear=YES` — clear band-change history |
| `/reboot` | POST | soft restart |
| `/factory_reset` | POST | `confirm=YES` |
| `/live` | GET | device live HTML page (opened in a browser) |

## Build & run

Requirements: macOS 13+, Xcode command-line tools (Swift 5.9+).

```bash
# Quick run from the CLI
swift run

# Or build a double-clickable .app into ./dist
./build-app.sh
open "dist/Band Pass Filter Controller.app"
```

You can also open the folder in Xcode (`File ▸ Open ▸ Package.swift`).

## First connection

1. Launch the app and open **Settings**.
2. Set **Device Address** to your controller's mDNS name (default
   `SO2R-BPF.local`) or its IP. On first boot the device runs a captive portal at
   `192.168.4.1` (SSID `BPF-Setup-XXXXXX`).
3. Click **Apply & Reconnect**. The badge turns green when `/status` responds.
4. Configure the Radio 1 / Radio 2 TCI servers and click **Save to Device**.
   For a single dual-receiver radio (e.g. SunSDR2 PRO) enter the *same* host:port
   in both Radio 1 and Radio 2 to use shared mode.

## Project layout

```
Sources/BandPassFilterController/
├── App.swift                     # @main scene
├── Models/                       # Band, DeviceStatus, RadioStatus, DeviceConfig
├── Networking/BPFClient.swift    # async HTTP client over the firmware API
├── ViewModels/ControllerViewModel.swift  # polling + persistence + actions
└── Views/                        # Dashboard, Controls, History, Settings, sidebar
```

> Note: the local firmware clone lives in a sibling folder
> `../BandPassFilterController`; this app is a separate Swift package.
