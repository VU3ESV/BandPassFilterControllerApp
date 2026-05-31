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
        .package(path: "../RadioPluginKit"),
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
