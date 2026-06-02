import SwiftUI
import RadioPluginKit

/// Plugin adapter for the Amateur Radio Suite container. Lives inside the
/// `BandPassFilterController` module for internal access to `ContentView` /
/// `ControllerViewModel`.
@MainActor
public final class BPFPlugin: RadioPlugin {
    public static let manifest: RadioPluginManifest? = RadioPluginManifest(
        id: "bpf",
        name: "Band Pass Filter",
        version: "1.0",
        isolation: .inProcess,                       // first-party, linked into the host
        capabilities: [.networkClient, .bonjour],
        systemImage: "line.3.horizontal.decrease.circle",
        author: "VU3ESV"
    )
    public static var metadata: PluginMetadata { manifest!.metadata }

    private let host: PluginHost
    private let model: ControllerViewModel
    private var started = false

    public init(host: PluginHost) {
        self.host = host
        AppDefaults.store = host.defaults(for: Self.metadata.id)
        self.model = ControllerViewModel()
    }

    public func makeRootView() -> AnyView {
        // ContentView consumes the view model via @EnvironmentObject.
        AnyView(ContentView().environmentObject(model))
    }

    public func activate() {
        guard !started else { return }
        started = true
        model.start()   // begins the HTTP polling loop
    }
}
