// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Output",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Output", targets: ["Output"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(name: "Output", dependencies: ["Core"]),
        .testTarget(name: "OutputTests", dependencies: ["Output", .product(name: "CoreTestSupport", package: "Core")]),
    ]
)
