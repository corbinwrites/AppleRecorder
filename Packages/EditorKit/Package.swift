// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EditorKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EditorKit", targets: ["EditorKit"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Theme"),
    ],
    targets: [
        .target(name: "EditorKit", dependencies: ["Core", "Theme"]),
        .testTarget(name: "EditorKitTests", dependencies: ["EditorKit", .product(name: "CoreTestSupport", package: "Core")]),
    ]
)
