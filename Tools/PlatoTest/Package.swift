// swift-tools-version:5.7
import PackageDescription
// Perft + search sanity for the chess and English-checkers engines, and the Plato board reader on real frames.
let package = Package(name: "PlatoTest", targets: [.executableTarget(name: "PlatoTest", path: "Sources/PlatoTest", swiftSettings: [.unsafeFlags(["-Ounchecked"])])])
