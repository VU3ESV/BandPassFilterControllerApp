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

                if let failure = model.bypassFailure {
                    failureBanner(failure)
                }

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
                // Device-reported state only; manual bypass shows as `tuning`.
                if let radio {
                    if radio.tuning {
                        Text("Bypass engaged (device confirmed)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    } else {
                        Text(radio.band.isBypass ? "Currently bypassed" : "On \(radio.band.label)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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

    // Stays up until a later bypass request succeeds, so a refused bypass
    // can't be missed even after the alert is dismissed.
    private func failureBanner(_ failure: ControllerViewModel.BypassFailure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.title2).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text(failure.title).font(.headline).foregroundStyle(.white)
                Text(failure.message).font(.callout).foregroundStyle(.white)
                Text(failure.advice).font(.callout.weight(.semibold)).foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            Button {
                model.bypassFailure = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
    }
}
