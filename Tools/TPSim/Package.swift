// swift-tools-version:5.7
import PackageDescription

// Tile Push self-play: the app's engine (copied in by .github/workflows/tpsim.yml) against other strategies.
let package = Package(
    name: "TPSim",
    targets: [
        .executableTarget(name: "TPSim", path: "Sources/TPSim", swiftSettings: [.unsafeFlags(["-Ounchecked"])])
    ]
)
