// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Enhance",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Enhance", targets: ["Enhance"]),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .target(name: "Enhance", dependencies: ["Core"]),
        .testTarget(name: "EnhanceTests", dependencies: ["Enhance", .product(name: "CoreTestSupport", package: "Core")]),
    ]
)
