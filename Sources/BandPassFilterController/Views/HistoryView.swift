import SwiftUI

/// Band-change history from the firmware's `/status` `history` ring buffer
/// (newest first), with a control to clear it (POST /history?clear=YES).
struct HistoryView: View {
    @EnvironmentObject private var model: ControllerViewModel
    @State private var showClearConfirm = false

    private var events: [BandEvent] {
        // Firmware sends oldest-first; show newest at the top.
        (model.status?.history ?? []).reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if events.isEmpty {
                    emptyState
                } else {
                    GroupBox {
                        VStack(spacing: 0) {
                            ForEach(Array(events.enumerated()), id: \.offset) { pair in
                                eventRow(pair.element)
                                if pair.offset < events.count - 1 { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("History").font(.largeTitle.bold())
                Text("Recent band changes recorded on the device (newest first).")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let count = model.status?.historyCount, count > 0 {
                Text("\(count) event\(count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(!model.connection.isOnline || events.isEmpty)
            .confirmationDialog("Clear the device's band-change history?",
                                isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { Task { await model.clearHistory() } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func eventRow(_ event: BandEvent) -> some View {
        HStack(spacing: 14) {
            // Band badge
            Text(event.band.label)
                .font(.callout.weight(.bold))
                .frame(width: 52)
                .foregroundStyle(event.band.isBypass ? Color.secondary : Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("BPF \(event.bpf)").font(.subheadline.weight(.medium))
                    Text(event.frequencyDisplay)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if event.tune { tag("ATU tune", .orange) }
                    if event.inhibit { tag("Bypass", .gray) }
                    if !event.band.isBypass { tag("code \(event.code)", .blue) }
                }
            }
            Spacer()
            Text(relativeTime(event))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    /// Event timestamps are device-uptime seconds; show them relative to the
    /// current uptime ("3m ago"). Falls back to an uptime stamp if unknown.
    private func relativeTime(_ event: BandEvent) -> String {
        guard let now = model.status?.uptimeSeconds, now >= event.uptimeSeconds else {
            return "@ \(event.uptimeSeconds)s"
        }
        let delta = now - event.uptimeSeconds
        if delta < 1 { return "just now" }
        if delta < 60 { return "\(delta)s ago" }
        if delta < 3600 { return "\(delta / 60)m ago" }
        if delta < 86400 { return "\(delta / 3600)h ago" }
        return "\(delta / 86400)d ago"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text(model.connection.isOnline
                 ? "No band changes recorded yet."
                 : "Connect to a device to see its history.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
