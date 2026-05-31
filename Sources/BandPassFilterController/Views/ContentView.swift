import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ControllerViewModel
    @State private var selection: SidebarItem = .dashboard

    enum SidebarItem: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case controls = "Controls"
        case settings = "Settings"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "antenna.radiowaves.left.and.right"
            case .controls: return "switch.2"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) {
                ConnectionBadge()
                    .padding(12)
            }
        } detail: {
            Group {
                switch selection {
                case .dashboard: DashboardView()
                case .controls: ControlsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar { ToolbarContent() }
        }
        .navigationTitle("Band Pass Filter Controller")
    }

    @ToolbarContentBuilder
    private func ToolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Fetch /status now")
        }
    }
}

/// Compact connection indicator pinned to the bottom of the sidebar.
struct ConnectionBadge: View {
    @EnvironmentObject private var model: ControllerViewModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).bold()
                Text(model.host).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch model.connection {
        case .online: return .green
        case .connecting: return .yellow
        case .idle: return .gray
        case .offline: return .red
        }
    }

    private var title: String {
        switch model.connection {
        case .online: return "Connected"
        case .connecting: return "Connecting…"
        case .idle: return "Idle"
        case .offline: return "Offline"
        }
    }
}
