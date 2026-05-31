import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: ControllerViewModel
    @State private var hostDraft: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").font(.largeTitle.bold())

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
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .onAppear {
            hostDraft = model.host
            model.prepareConfigDraft()
        }
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

    private func applyHost() {
        let trimmed = hostDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.host = trimmed
        model.restart()
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
