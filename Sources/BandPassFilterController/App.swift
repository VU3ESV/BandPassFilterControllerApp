import SwiftUI

@main
struct BandPassFilterControllerApp: App {
    @StateObject private var model = ControllerViewModel()

    var body: some Scene {
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
