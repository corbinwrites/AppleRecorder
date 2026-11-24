// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Theme",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Theme", targets: ["Theme"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(name: "Theme", dependencies: ["Core"]),
        .testTarget(name: "ThemeTests", dependencies: ["Theme", .product(name: "CoreTestSupport", package: "Core")]),
    ]
)
