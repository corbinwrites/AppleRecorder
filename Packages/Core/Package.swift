// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "CoreTestSupport", targets: ["CoreTestSupport"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "CoreTestSupport", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core", "CoreTestSupport"]),
    ]
)
