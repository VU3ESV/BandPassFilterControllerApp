import Foundation
import SwiftUI

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

    // Editable config draft (Settings screen)
    @Published var configDraft = DeviceConfig()
    @Published var configMessage: String?
    @Published var isSavingConfig = false
    @Published var isLoadingConfig = false
    /// True once the draft has been populated from the device (vs. defaults),
    /// so the Settings screen doesn't re-fetch and clobber in-progress edits.
    @Published private(set) var configLoaded = false

    private var pollTask: Task<Void, Never>?

    var client: BPFClient { BPFClient(host: host) }

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
            if identity == nil { identity = try? await client.fetchDiscover() }
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
            // Re-sync the draft with what the device actually stored, so the
            // form shows the persisted values (and any clamping the firmware did).
            if let fresh = try? await client.fetchConfig() { configDraft = fresh }
        } catch {
            configMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Controls

    func setBypass(bpf: Int, on: Bool) async {
        do {
            try await client.setBypass(bpf: bpf, on: on)
            await refresh()
        } catch {
            connection = .offline(error.localizedDescription)
        }
    }

    func reboot() async {
        try? await client.reboot()
        connection = .offline("Rebooting…")
        status = nil
    }

    func factoryReset() async {
        try? await client.factoryReset()
        connection = .offline("Factory reset — device rebooting…")
        status = nil
    }

    // MARK: - History

    func clearHistory() async {
        do {
            try await client.clearHistory()
            await refresh()
        } catch {
            connection = .offline(error.localizedDescription)
        }
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
