// swift-tools-version:5.7
import PackageDescription
// Runs the app's Crazy Alpaca reader + planner on real frames (PPM) on Linux. See .github/workflows/alpacatest.yml.
let package = Package(name: "AlpacaTest", targets: [.executableTarget(name: "AlpacaTest", path: "Sources/AlpacaTest", swiftSettings: [.unsafeFlags(["-Ounchecked"])])])
