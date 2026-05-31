// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BandPassFilterController",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BandPassFilterController", targets: ["BandPassFilterController"])
    ],
    targets: [
        .executableTarget(
            name: "BandPassFilterController",
            path: "Sources/BandPassFilterController"
        )
    ]
)
