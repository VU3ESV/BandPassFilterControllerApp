// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BandPassFilterControllerApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Standalone .app
        .executable(name: "BandPassFilterController", targets: ["BandPassFilterControllerMain"]),
        // Plugin library consumed by the Amateur Radio Suite container
        .library(name: "BandPassFilterControllerKit", targets: ["BandPassFilterController"]),
    ],
    dependencies: [
        // Consume RadioPluginKit as a published library by Git URL (same as the
        // other plugin apps and the suite) so the whole dependency graph resolves
        // one identical RadioPluginKit — avoids the path-vs-URL identity conflict
        // when hosted in the AmateurRadioApps container.
        .package(url: "https://github.com/VU3ESV/RadioPluginKit.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "BandPassFilterController",
            dependencies: [
                .product(name: "RadioPluginKit", package: "RadioPluginKit"),
            ],
            path: "Sources/BandPassFilterController"
        ),
        .executableTarget(
            name: "BandPassFilterControllerMain",
            dependencies: ["BandPassFilterController"],
            path: "Sources/BandPassFilterControllerMain"
        ),
    ]
)
