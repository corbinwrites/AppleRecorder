// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pipeline",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Pipeline", targets: ["Pipeline"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Enhance"),
        .package(path: "../Output"),
    ],
    targets: [
        .target(name: "Pipeline", dependencies: ["Core", "Enhance", "Output"]),
        .testTarget(name: "PipelineTests", dependencies: ["Pipeline", .product(name: "CoreTestSupport", package: "Core")]),
    ]
)
