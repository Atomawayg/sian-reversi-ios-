// swift-tools-version:5.7
import PackageDescription

// Engine-vs-engine matches, run by .github/workflows/arena.yml.
// The workflow copies the app's current engines and the baseline versions (renamed *V0) into Sources/Arena.
let package = Package(
    name: "Arena",
    targets: [
        .executableTarget(name: "Arena", path: "Sources/Arena",
                          swiftSettings: [.unsafeFlags(["-Ounchecked"])])
    ]
)
