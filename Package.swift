// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pandalytics",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "Pandalytics",
            targets: ["Pandalytics"]
        ),
    ],
    targets: [
        .target(
            name: "Pandalytics",
            path: "Sources/Pandalytics"
        ),
        .testTarget(
            name: "PandalyticsTests",
            dependencies: ["Pandalytics"],
            path: "Tests/PandalyticsTests"
        ),
    ]
)
