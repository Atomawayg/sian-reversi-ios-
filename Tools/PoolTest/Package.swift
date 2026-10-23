// swift-tools-version:5.7
import PackageDescription
// Runs the app's pool reader + shot engine on real frames (PPM) on Linux. See .github/workflows/pooltest.yml.
let package = Package(name: "PoolTest", targets: [.executableTarget(name: "PoolTest", path: "Sources/PoolTest", swiftSettings: [.unsafeFlags(["-Ounchecked"])])])
