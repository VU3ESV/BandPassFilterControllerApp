import SwiftUI

/// Public entry point for hosting the Band Pass Filter controller **out-of-process** as an
/// ExtensionKit `.appex`. The extension target is a separate module, so this factory hands
/// it the same UI the in-process `BPFPlugin` shows while every other type stays `internal`.
/// See `Xcode/Extension/BPFPluginExtension.swift`.
public enum BPFExtension {
    /// Build the controller root view for an out-of-process host. `defaults` backs the app's
    /// `@AppStorage`; the model's polling loop is started here (mirroring `BPFPlugin.activate()`).
    @MainActor
    public static func rootView(defaults: UserDefaults? = nil) -> AnyView {
        if let defaults { AppDefaults.store = defaults }
        let model = ControllerViewModel()
        model.start()
        return AnyView(ContentView().environmentObject(model))
    }
}
