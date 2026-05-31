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
        // RadioPluginKit is consumed as a published library by Git URL, so both
        // this repo's CI (which checks out only this repo) and the suite container
        // resolve the same tag — no sibling checkout required.
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
