import SwiftUI

struct ControlsView: View {
    @EnvironmentObject private var model: ControllerViewModel
    @State private var showFactoryConfirm = false
    @State private var showRebootConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Controls").font(.largeTitle.bold())

                bypassSection
                maintenanceSection
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private var bypassSection: some View {
        GroupBox("Manual Bypass") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Force a filter into bypass, or hand control back to TCI. Mirrors POST /bypass.")
                    .font(.callout).foregroundStyle(.secondary)

                bypassRow(bpf: 1, radio: model.status?.r1)
                Divider()
                bypassRow(bpf: 2, radio: model.status.map { $0.isSharedMode ? $0.r1 : $0.r2 })
            }
            .padding(4)
        }
    }

    private func bypassRow(bpf: Int, radio: RadioStatus?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("BPF \(bpf)").font(.headline)
                if let radio {
                    Text(radio.band.isBypass ? "Currently bypassed" : "On \(radio.band.label)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Bypass ON") {
                Task { await model.setBypass(bpf: bpf, on: true) }
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Button("Bypass OFF") {
                Task { await model.setBypass(bpf: bpf, on: false) }
            }
            .buttonStyle(.bordered)
            .tint(.green)
        }
        .disabled(!model.connection.isOnline)
    }

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
                }
                Divider()
                HStack {
                    VStack(alignment: .leading) {
                        Text("Factory Reset").font(.headline).foregroundStyle(.red)
                        Text("Zeros EEPROM and reboots into the setup portal. This erases all config.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Factory Reset…", role: .destructive) { showFactoryConfirm = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
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
        }
    }
}
