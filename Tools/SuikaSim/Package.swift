// swift-tools-version:5.7
import PackageDescription

// Plays whole fruit-game games in the app's own physics to compare strategy weights (.github/workflows/suika-sim.yml).
// The workflow copies App/SuikaEngine.swift and Shared/SuikaShared.swift into Sources/SuikaSim.
let package = Package(
    name: "SuikaSim",
    targets: [.executableTarget(name: "SuikaSim", path: "Sources/SuikaSim", swiftSettings: [.unsafeFlags(["-Ounchecked"])])]
)
