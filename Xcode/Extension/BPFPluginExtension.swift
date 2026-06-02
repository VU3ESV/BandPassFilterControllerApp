import SwiftUI
import ExtensionFoundation
import ExtensionKit
import BandPassFilterController

/// Band Pass Filter controller as a sandboxed, crash-isolated ExtensionKit `.appex` for the
/// Amateur Radio Suite. Declares the suite's extension point (see Info.plist) and vends the
/// controller UI via `BPFExtension.rootView()`; the suite embeds it with `EXHostViewController`.
///
/// SwiftPM cannot build `.appex` bundles — this target is built by the Xcode project
/// (`Xcode/project.yml`). The standalone app and the in-process `BPFPlugin` are unchanged.
@main
struct BPFPluginExtension: AppExtension {
    var configuration: AppExtensionSceneConfiguration {
        AppExtensionSceneConfiguration(
            PrimitiveAppExtensionScene(id: "primary") {
                BPFExtension.rootView()
            }
        )
    }
}
