// swift-tools-version:5.7
import PackageDescription

// Runs the fruit-game screen reader and AI on saved screenshots (raw RGB), on Linux in CI.
let package = Package(
    name: "SuikaTest",
    targets: [
        .executableTarget(name: "SuikaTest", path: "Sources/SuikaTest",
                          swiftSettings: [.unsafeFlags(["-O"])])
    ]
)
