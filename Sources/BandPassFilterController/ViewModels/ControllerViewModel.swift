import Foundation
import SwiftUI
import AppKit

/// Drives the whole UI: persists the device address, polls `/status`,
/// and exposes actions (save config, bypass, reboot, factory reset).
@MainActor
final class ControllerViewModel: ObservableObject {

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case online
        case offline(String)

        var isOnline: Bool { if case .online = self { return true } else { return false } }
    }

    /// A manual-bypass request the device did not apply. Safety-relevant: the
    /// user may be about to tune an ATU at high power, so it is shown as an
    /// alert plus a banner on Controls until a later bypass request succeeds.
    struct BypassFailure: Identifiable, Equatable {
        let id = UUID()
        let bpf: Int
        let on: Bool
        let message: String

        var title: String { "BPF \(bpf) bypass \(on ? "ON" : "OFF") was NOT applied" }
        var advice: String {
            on ? "Don't rely on BPF \(bpf) being in bypass. Do not tune at high power until Controls shows bypass engaged."
               : "BPF \(bpf) may still be forced to bypass."
        }
    }

    // Persisted settings
    @AppStorage("device.host", store: AppDefaults.store) var host: String = "SO2R-BPF.local"
    @AppStorage("poll.interval", store: AppDefaults.store) var pollInterval: Double = 1.5
    @AppStorage("poll.enabled", store: AppDefaults.store) var pollingEnabled: Bool = true

    // Live state
    @Published private(set) var status: DeviceStatus?
    @Published private(set) var connection: ConnectionState = .idle
    @Published private(set) var lastUpdated: Date?
    /// Static identity from `GET /discover`, fetched once per connection.
    @Published private(set) var identity: DeviceIdentity?

    // Device auth (firmware ≥ v0.6.0)
    /// Hostname the firmware itself reports (`/discover`, else fetched `/config`);
    /// the Keychain account for its password. Never the editable draft.
    @Published private(set) var deviceHostname: String?
    @Published private(set) var hasDevicePassword = false
    @Published var passwordMessage: String?
    /// Read from the Keychain when the hostname becomes known, so any Keychain
    /// access prompt appears at connect time rather than mid-bypass.
    private var devicePassword: String?

    // Action feedback
    @Published var bypassFailure: BypassFailure?
    @Published var showBypassAlert = false
    @Published var historyMessage: String?
    @Published var maintenanceMessage: String?

    // Editable config draft (Settings screen)
    @Published var configDraft = DeviceConfig()
    @Published var configMessage: String?
    @Published var isSavingConfig = false
    @Published var isLoadingConfig = false
    /// True once the draft has been populated from the device (vs. defaults),
    /// so the Settings screen doesn't re-fetch and clobber in-progress edits.
    @Published private(set) var configLoaded = false

    private var pollTask: Task<Void, Never>?

    var client: BPFClient { BPFClient(host: host, password: devicePassword) }

    /// `/discover` says a password is set but we have none to offer.
    var needsDevicePassword: Bool { (identity?.requiresAuth ?? false) && !hasDevicePassword }

    // MARK: - Polling lifecycle

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Restart polling, e.g. after the user changes the host or interval.
    func restart() {
        stop()
        status = nil
        identity = nil
        deviceHostname = nil
        devicePassword = nil
        hasDevicePassword = false
        passwordMessage = nil
        bypassFailure = nil
        connection = .idle
        start()
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            if pollingEnabled {
                await refresh()
            }
            let nanos = UInt64(max(0.5, pollInterval) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
    }

    func refresh() async {
        if status == nil { connection = .connecting }
        do {
            let fresh = try await client.fetchStatus()
            status = fresh
            connection = .online
            lastUpdated = Date()
            // Identity is static; fetch it once per connection after we're online.
            if identity == nil {
                identity = try? await client.fetchDiscover()
                adoptHostname(identity?.hostname)
            }
        } catch {
            connection = .offline(error.localizedDescription)
        }
    }

    /// Point the app at a discovered device and reconnect.
    func use(_ device: DiscoveredDevice) {
        guard !device.address.isEmpty else { return }
        host = device.address
        configLoaded = false
        restart()
        Task { await loadConfigFromDevice() }
    }

    // MARK: - Config

    /// Pull the device's stored configuration into the editable draft so the
    /// Settings screen reflects what the controller is actually running (host,
    /// port, IARU region, SSID, hostname) rather than app-side defaults.
    /// On failure (device offline / old firmware without `/config`) it falls
    /// back to seeding the hostname from the address and leaves a note.
    func loadConfigFromDevice() async {
        isLoadingConfig = true
        defer { isLoadingConfig = false }
        do {
            configDraft = try await client.fetchConfig()
            configLoaded = true
            configMessage = nil
            if deviceHostname == nil { adoptHostname(configDraft.hostname) }
        } catch {
            prepareConfigDraft()
            configMessage = "Couldn't read current config from device: \(error.localizedDescription)"
        }
    }

    /// Seed the editable draft from the persisted address + last known status.
    func prepareConfigDraft() {
        // Hostname is the part of `host` before ".local" when applicable.
        if configDraft.hostname.isEmpty || configDraft.hostname == "SO2R-BPF" {
            let base = host.lowercased().hasSuffix(".local")
                ? String(host.dropLast(".local".count))
                : host
            if !base.contains(".") && !base.contains(":") {
                configDraft.hostname = base
            }
        }
    }

    func saveConfig() async {
        isSavingConfig = true
        configMessage = nil
        defer { isSavingConfig = false }
        do {
            try await client.saveConfig(configDraft)
            configMessage = "Saved. The device may reboot to apply network changes."
            carryPasswordToRenamedDevice(configDraft.hostname)
            // Re-sync the draft with what the device actually stored, so the
            // form shows the persisted values (and any clamping the firmware did).
            if let fresh = try? await client.fetchConfig() { configDraft = fresh }
        } catch {
            configMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Controls

    /// Never optimistic: the Controls view shows bypass only from `/status`,
    /// which is re-read after the request whether or not it succeeded.
    func setBypass(bpf: Int, on: Bool) async {
        do {
            try await client.setBypass(bpf: bpf, on: on)
            bypassFailure = nil
        } catch {
            bypassFailure = BypassFailure(bpf: bpf, on: on, message: error.localizedDescription)
            showBypassAlert = true
            NSSound.beep()
        }
        await refresh()
    }

    func reboot() async {
        maintenanceMessage = nil
        do {
            try await client.reboot()
            connection = .offline("Rebooting…")
            status = nil
        } catch {
            maintenanceMessage = "Reboot failed: \(error.localizedDescription)"
        }
    }

    func factoryReset() async {
        maintenanceMessage = nil
        do {
            try await client.factoryReset()
            connection = .offline("Factory reset — device rebooting…")
            status = nil
        } catch {
            maintenanceMessage = "Factory reset failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Device password (Keychain)

    /// Switch the Keychain account to the hostname the device reports and load
    /// its password. Only reads the secret when an item exists.
    private func adoptHostname(_ name: String?) {
        guard let name, !name.isEmpty, name != deviceHostname else { return }
        deviceHostname = name
        let exists = DeviceKeychain.hasPassword(for: name)
        devicePassword = exists ? DeviceKeychain.password(for: name) : nil
        hasDevicePassword = devicePassword != nil
        if exists && devicePassword == nil {
            passwordMessage = "A Keychain item exists for \(name) but the app couldn't read it (access denied?). Re-enter the password to replace it."
        }
    }

    func saveDevicePassword(_ password: String) {
        guard let account = deviceHostname, !password.isEmpty else { return }
        do {
            try DeviceKeychain.setPassword(password, for: account)
            devicePassword = password
            hasDevicePassword = true
            passwordMessage = "Saved to Keychain for \(account)."
        } catch {
            passwordMessage = "Couldn't save to Keychain: \(error.localizedDescription)"
        }
    }

    func forgetDevicePassword() {
        guard let account = deviceHostname else { return }
        do {
            try DeviceKeychain.deletePassword(for: account)
            devicePassword = nil
            hasDevicePassword = false
            passwordMessage = "Removed from Keychain for \(account)."
        } catch {
            passwordMessage = "Couldn't remove from Keychain: \(error.localizedDescription)"
        }
    }

    /// The Keychain account follows the hostname, so after a successful rename
    /// store the in-memory password under the new name too (the old item stays).
    private func carryPasswordToRenamedDevice(_ newHostname: String) {
        guard let password = devicePassword, !newHostname.isEmpty,
              newHostname != deviceHostname,
              !DeviceKeychain.hasPassword(for: newHostname) else { return }
        try? DeviceKeychain.setPassword(password, for: newHostname)
    }

    // MARK: - History

    func clearHistory() async {
        historyMessage = nil
        do {
            try await client.clearHistory()
        } catch {
            historyMessage = "Clear failed: \(error.localizedDescription)"
        }
        await refresh()
    }

    // MARK: - Backup / Restore

    /// Write the device's `/config` JSON (a portable backup) to `url`.
    func backupConfig(to url: URL) async {
        configMessage = nil
        do {
            let data = try await client.fetchConfigData()
            try data.write(to: url, options: .atomic)
            configMessage = "Backed up config to \(url.lastPathComponent)."
        } catch {
            configMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    /// Load a previously backed-up `/config` JSON file into the editable draft.
    /// Does not push to the device — the user reviews, then taps Save.
    func restoreConfig(from url: URL) async {
        configMessage = nil
        do {
            let data = try Data(contentsOf: url)
            configDraft = try JSONDecoder().decode(DeviceConfig.self, from: data)
            configLoaded = true
            configMessage = "Loaded \(url.lastPathComponent) into the form — review, then Save to Device."
        } catch {
            configMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - External pages

    /// Device web portal / live page URLs for opening in the user's browser.
    var webPortalURL: URL? { client.pageURL() }
    var livePageURL: URL? { client.pageURL("live") }
}
