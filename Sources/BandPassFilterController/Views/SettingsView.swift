import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: ControllerViewModel
    @StateObject private var discovery = DiscoveryService()
    @State private var hostDraft: String = ""
    @State private var showRebootConfirm = false
    @State private var showFactoryConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Text("Settings").font(.largeTitle.bold())
                    if model.isLoadingConfig {
                        ProgressView().controlSize(.small)
                        Text("Reading current config…")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }

                connectionSection
                radioSection(title: "Radio 1 (TCI Server)",
                             host: $model.configDraft.radio1Host,
                             port: $model.configDraft.radio1Port,
                             iaru: $model.configDraft.radio1IARU)
                radioSection(title: "Radio 2 (TCI Server)",
                             host: $model.configDraft.radio2Host,
                             port: $model.configDraft.radio2Port,
                             iaru: $model.configDraft.radio2IARU,
                             footnote: "In shared mode, set Radio 2 to the same host:port as Radio 1.")
                networkSection

                if let message = model.configMessage {
                    Label(message, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        Task { await model.saveConfig() }
                    } label: {
                        if model.isSavingConfig {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save to Device")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSavingConfig)

                    Text("Pushes config via POST /save (same as the web portal).")
                        .font(.caption).foregroundStyle(.secondary)
                }

                backupRestoreSection
                devicePagesSection
                maintenanceSection
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .onAppear {
            hostDraft = model.host
            // Pull the controller's real settings into the draft the first time
            // the screen appears; don't re-fetch on later appearances so we
            // never clobber edits the user has started.
            if !model.configLoaded {
                Task { await model.loadConfigFromDevice() }
            }
            discovery.start()   // browse the LAN for _bpf-so2r._tcp controllers
        }
        .onDisappear { discovery.stop() }
        .onChange(of: model.host) { newHost in hostDraft = newHost }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        GroupBox("App Connection") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(label: "Device Address") {
                    TextField("SO2R-BPF.local or 192.168.4.1", text: $hostDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(applyHost)
                }
                Text("mDNS hostname (default SO2R-BPF.local) or IP. The captive portal lives at 192.168.4.1.")
                    .font(.caption).foregroundStyle(.secondary)

                if let id = model.identity {
                    Label("\(id.productName) \(id.versionDisplay) · \(id.hostname ?? model.host)",
                          systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                }

                discoverySubsection

                HStack {
                    Toggle("Live polling", isOn: $model.pollingEnabled)
                    Spacer()
                    Stepper("Every \(model.pollInterval, specifier: "%.1f") s",
                            value: $model.pollInterval, in: 0.5...10, step: 0.5)
                }

                HStack {
                    Button("Apply & Reconnect", action: applyHost)
                        .buttonStyle(.bordered)
                    Spacer()
                }
            }
            .padding(4)
        }
    }

    // mDNS auto-discovery of `_bpf-so2r._tcp` controllers on the LAN.
    @ViewBuilder
    private var discoverySubsection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("Discovered on network", systemImage: "dot.radiowaves.up.forward")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                if discovery.isBrowsing { ProgressView().controlSize(.mini) }
                Spacer()
                Button {
                    discovery.restart()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Re-scan the network")
            }

            if discovery.devices.isEmpty {
                Text(discovery.isBrowsing ? "Searching…" : "No controllers found yet.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(discovery.devices) { device in
                    discoveredRow(device)
                }
            }
        }
    }

    private func discoveredRow(_ device: DiscoveredDevice) -> some View {
        let isCurrent = device.address == model.host
        return Button {
            model.use(device)
            hostDraft = device.address
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.title).font(.callout.weight(.medium))
                    Text([device.address, device.version.map { "v\($0)" }]
                        .compactMap { $0 }.joined(separator: "  ·  "))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    Text("Current").font(.caption2).foregroundStyle(.green)
                } else {
                    Image(systemName: "arrow.right.circle").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4).padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func radioSection(title: String,
                              host: Binding<String>,
                              port: Binding<Int>,
                              iaru: Binding<Int>,
                              footnote: String? = nil) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(label: "Host") {
                    TextField("192.168.1.50", text: host)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 16) {
                    LabeledField(label: "Port") {
                        TextField("50001", value: port, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    LabeledField(label: "IARU Region") {
                        Picker("", selection: iaru) {
                            Text("Keep current").tag(0)
                            Text("Region 1").tag(1)
                            Text("Region 2").tag(2)
                            Text("Region 3").tag(3)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    Spacer()
                }
                if let footnote {
                    Text(footnote).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }

    private var networkSection: some View {
        GroupBox("Device Network") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(label: "Hostname (mDNS)") {
                    TextField("SO2R-BPF", text: $model.configDraft.hostname)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField(label: "Wi-Fi SSID") {
                    TextField("Network name", text: $model.configDraft.wifiSSID)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField(label: "Wi-Fi Password") {
                    SecureField("Leave blank to keep current", text: $model.configDraft.wifiPassword)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Changing Wi-Fi or hostname usually reboots the device; reconnect afterwards.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    // Backup downloads the device's /config JSON; Restore loads such a file
    // back into the form for review before Save (mirrors the web portal).
    private var backupRestoreSection: some View {
        GroupBox("Backup / Restore") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        backupConfig()
                    } label: { Label("Back Up Config…", systemImage: "square.and.arrow.down") }
                        .disabled(!model.connection.isOnline)
                    Button {
                        restoreConfig()
                    } label: { Label("Restore from File…", systemImage: "square.and.arrow.up") }
                    Spacer()
                }
                Text("Backup saves the device's /config as JSON. Restore loads it into the form above — review, then Save to Device. The Wi-Fi password is never included.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    // Quick links to the device's own web pages (portal + live view).
    private var devicePagesSection: some View {
        GroupBox("Device Web Pages") {
            HStack {
                Button {
                    if let url = model.webPortalURL { NSWorkspace.shared.open(url) }
                } label: { Label("Open Web Portal", systemImage: "safari") }
                Button {
                    if let url = model.livePageURL { NSWorkspace.shared.open(url) }
                } label: { Label("Open Live Page", systemImage: "dot.radiowaves.left.and.right") }
                Spacer()
            }
            .padding(4)
        }
    }

    private func backupConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue =
            "bpf-so2r-config-\(model.configDraft.hostname.isEmpty ? "device" : model.configDraft.hostname).json"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.backupConfig(to: url) }
        }
    }

    private func restoreConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.restoreConfig(from: url) }
        }
    }

    // Mirrors the Reboot / Factory reset controls at the bottom of the web portal.
    private var maintenanceSection: some View {
        GroupBox("Maintenance") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Reboot Device").font(.headline)
                        Text("Soft restart (POST /reboot).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reboot…") { showRebootConfirm = true }
                        .buttonStyle(.bordered)
                        .disabled(!model.connection.isOnline)
                }
                Divider()
                HStack {
                    VStack(alignment: .leading) {
                        Text("Factory Reset").font(.headline).foregroundStyle(.red)
                        Text("Zeros EEPROM and reboots into the BPF-Setup portal. This erases all config.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Factory Reset…", role: .destructive) { showFactoryConfirm = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(!model.connection.isOnline)
                }
            }
            .padding(4)
        }
        .confirmationDialog("Reboot the device now?",
                            isPresented: $showRebootConfirm, titleVisibility: .visible) {
            Button("Reboot", role: .destructive) { Task { await model.reboot() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Factory reset will erase all settings and reboot into the BPF-Setup portal. Continue?",
                            isPresented: $showFactoryConfirm, titleVisibility: .visible) {
            Button("Erase & Reset", role: .destructive) { Task { await model.factoryReset() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Wi-Fi credentials, hostname and both radio endpoints will be wiped.")
        }
    }

    private func applyHost() {
        let trimmed = hostDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.host = trimmed
        model.restart()
        // New address → re-read config from that device.
        Task { await model.loadConfigFromDevice() }
    }
}

/// Small label-over-control layout helper.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
