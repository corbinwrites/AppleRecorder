// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Transcribe",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Transcribe", targets: ["Transcribe"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Capture"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "Transcribe",
            dependencies: [
                "Core",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .testTarget(
            name: "TranscribeTests",
            dependencies: [
                "Transcribe",
                .product(name: "Capture", package: "Capture"),
                .product(name: "CoreTestSupport", package: "Core"),
            ]
        ),
    ]
)
