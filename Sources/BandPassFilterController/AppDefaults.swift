import Foundation

/// Backing store for this app's `@AppStorage` keys.
///
/// Standalone: `store` stays `nil`, so `@AppStorage` uses `UserDefaults.standard`.
/// In the suite: `BPFPlugin` sets `store` to a per-plugin suite at construction,
/// before any view/view-model is built, so keys like "device.host" don't collide
/// with other plugins sharing the container's process.
enum AppDefaults {
    static var store: UserDefaults?
    static var resolved: UserDefaults { store ?? .standard }
}
