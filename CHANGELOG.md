# Changelog

All notable changes to the **Band Pass Filter Controller** macOS app, which also ships as
an [Amateur Radio Suite](https://github.com/VU3ESV/AmateurRadioSuite) plugin. Format follows
[Keep a Changelog](https://keepachangelog.com/); a release is cut on every PR merge to `main`
(minor bump, tags `vX.Y.Z`).

## [Unreleased]

### Fixed
- **The Suite plugin reports the app's release version.** The `.radioplugin`'s `plugin.json`
  and the `.appex` (standalone and embedded) said 1.0.0 / 1.0 in every release, so the Amateur
  Radio Suite couldn't tell a new plugin from an old one. `make-radioplugin.sh` and
  `package-signed.sh` now pass `VERSION` (leading `v` dropped) as `MARKETING_VERSION` /
  `CURRENT_PROJECT_VERSION` and `plugin.json`'s `__VERSION__` is stamped; both scripts stop if the
  built version doesn't match. Same mechanism as LP-700-App#22 / LP-100A-App#14.

### Added
- **Device password (firmware v0.6.0 auth)**: answers the controller's HTTP Digest
  challenge as `admin` with a password stored in the login Keychain
  (service `BandPassFilterController`, account = device hostname), set from
  Settings ▸ Device Password. A Basic challenge is refused, so the password never
  crosses the LAN in clear. A 401 is a typed error ("Device requires a password" /
  "Device rejected the password"). A refused bypass beeps, raises an alert and keeps a
  red banner on Controls, and the UI only shows bypass once `/status` confirms it. Save,
  clear-history, reboot and factory-reset failures are shown inline instead of being
  swallowed. Settings warns when `/discover` reports `auth_required` and no password is
  stored. First unit-test target (`swift test`).
- **Out-of-process plugin + pipeline** ([CONVERTING-A-PLUGIN.md](https://github.com/VU3ESV/AmateurRadioSuite/blob/main/docs/CONVERTING-A-PLUGIN.md)):
  an ExtensionKit `.appex` target + `scripts/make-radioplugin.sh` packaging `BPF.radioplugin`,
  so the suite can browse/install the controller and host it sandboxed via
  `EXHostViewController`. Adds a public `BPFExtension.rootView()` factory; the standalone app
  and in-process `BPFPlugin` are unchanged. CI builds the `.appex` on every PR, and each
  release attaches `BandPassFilterController-<version>.radioplugin` **alongside** the app.

### Changed
- **App is now published as a `.dmg`** (`scripts/make-dmg.sh`) instead of a `.zip`, matching
  LP-700 / LP-100A. The `.radioplugin` remains an additional artifact on the same release.

## [0.3.0] — 2026-06-02
### Added
- **CI + Release pipelines** ([#7](https://github.com/VU3ESV/BandPassFilterControllerApp/pull/7)):
  build/test on every PR; a minor-version GitHub Release with the macOS `.app` zip on each
  merge to `main`.
- **Plugin architecture** ([#4](https://github.com/VU3ESV/BandPassFilterControllerApp/pull/4)):
  a `public BPFPlugin` adapter conforming to `RadioPlugin` lets the Amateur Radio Suite host
  the controller in-process; all views/view-models/networking stay `internal`.
### Changed
- **RadioPluginKit** adopted via Git URL and bumped to 1.2.1; synced the 1.2 manifest with
  the suite contract ([#5](https://github.com/VU3ESV/BandPassFilterControllerApp/pull/5),
  [#6](https://github.com/VU3ESV/BandPassFilterControllerApp/pull/6),
  [#8](https://github.com/VU3ESV/BandPassFilterControllerApp/pull/8)).

## [0.2.0] — 2026-05-31
### Added
- **LAN auto-discovery** ([#3](https://github.com/VU3ESV/BandPassFilterControllerApp/pull/3)):
  Bonjour/mDNS `_bpf-so2r._tcp` plus `GET /discover`.
- **Firmware v0.5.0 support** ([#2](https://github.com/VU3ESV/BandPassFilterControllerApp/pull/2)):
  version reporting, RF sensors, history, and backup/restore.
- Load device config from `/config`; move reboot & factory reset into Settings
  ([#1](https://github.com/VU3ESV/BandPassFilterControllerApp/pull/1)).

## [0.1.0] — 2026-05-31
### Added
- Initial macOS SwiftUI app for the Band Pass Filter Controller, with a bundled
  band-pass-response app icon.
