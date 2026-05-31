import SwiftUI

struct ControlsView: View {
    @EnvironmentObject private var model: ControllerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Controls").font(.largeTitle.bold())

                bypassSection
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
}
