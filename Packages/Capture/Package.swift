// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Capture",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Capture", targets: ["Capture"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(name: "Capture", dependencies: ["Core"]),
        .testTarget(name: "CaptureTests", dependencies: ["Capture", .product(name: "CoreTestSupport", package: "Core")]),
    ]
)
