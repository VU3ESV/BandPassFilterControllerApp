import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: ControllerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let status = model.status {
                    filterGrid(status)
                    deviceInfo(status)
                } else {
                    placeholder
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Filter Status").font(.largeTitle.bold())
                if let status = model.status {
                    Text(status.isSharedMode
                         ? "Shared mode — one TCI server feeds both filters"
                         : "Dual mode — independent TCI server per filter")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let updated = model.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func filterGrid(_ status: DeviceStatus) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)], spacing: 16) {
            FilterCardView(index: 1, radio: status.r1)
            FilterCardView(index: 2, radio: status.isSharedMode ? status.r1 : status.r2)
        }
    }

    private func deviceInfo(_ status: DeviceStatus) -> some View {
        GroupBox("Device") {
            VStack(spacing: 0) {
                infoRow("Wi-Fi", status.apMode ? "Access Point" : (status.wifiUp ? "Connected" : "Down"),
                        systemImage: "wifi", ok: status.wifiUp || status.apMode)
                Divider()
                infoRow("IP Address", status.ip ?? "—", systemImage: "network")
                Divider()
                infoRow("Signal", status.rssi.map { "\($0) dBm" } ?? "—",
                        systemImage: "cellularbars")
                Divider()
                infoRow("Mode", status.mode.capitalized, systemImage: "rectangle.2.swap")
                Divider()
                infoRow("Uptime", status.uptimeDisplay, systemImage: "clock")
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, systemImage: String, ok: Bool? = nil) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(ok == false ? .red : .primary)
                .fontWeight(.medium)
        }
        .padding(.vertical, 8)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(placeholderText).foregroundStyle(.secondary)
            if case .offline = model.connection {
                Button("Retry") { Task { await model.refresh() } }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var placeholderText: String {
        switch model.connection {
        case .offline(let message): return "Cannot reach \(model.host)\n\(message)"
        case .connecting: return "Connecting to \(model.host)…"
        default: return "Waiting for device…"
        }
    }
}

/// A single band-pass filter status card.
struct FilterCardView: View {
    let index: Int
    let radio: RadioStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BPF \(index)").font(.title3.bold())
                Spacer()
                activityPill
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(radio.band.label)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(radio.band.isBypass ? Color.secondary : Color.accentColor)
                if !radio.band.isBypass {
                    Text("· code \(radio.band.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Label(radio.frequencyDisplay, systemImage: "waveform.path")
                    .font(.callout.monospacedDigit())
                Spacer()
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                statusChip(radio.connected ? "TCI Linked" : "No Link",
                           color: radio.connected ? .green : .red)
                if radio.tuning {
                    statusChip("Bypass (ATU)", color: .orange)
                } else if radio.band.isBypass {
                    statusChip("Bypass", color: .gray)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1.5)
        )
    }

    private var borderColor: Color {
        if !radio.connected { return .red.opacity(0.4) }
        if radio.tuning { return .orange.opacity(0.6) }
        return .green.opacity(0.35)
    }

    private var activityPill: some View {
        Text(radio.activity.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(activityColor.opacity(0.18), in: Capsule())
            .foregroundStyle(activityColor)
    }

    private var activityColor: Color {
        switch radio.activity {
        case .receiving: return .green
        case .tuning: return .orange
        case .offline: return .red
        }
    }

    private func statusChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
