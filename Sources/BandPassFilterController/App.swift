import SwiftUI

/// Standalone-app entry. In the suite this type is unused (the container owns
/// the process); the plugin path is `BPFPlugin`. Kept `public` so the thin
/// `BandPassFilterControllerMain` executable target can call `.main()` on it.
public struct BandPassFilterStandaloneApp: App {
    @StateObject private var model = ControllerViewModel()

    public init() {}

    public var body: some Scene {
        WindowGroup("Band Pass Filter Controller") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 560)
                .onAppear { model.start() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
