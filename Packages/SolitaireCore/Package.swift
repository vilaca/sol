// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SolitaireCore",
    // iOS 16 runs on iPhone 8 / X / SE (2nd gen) and every later model.
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SolitaireCore", targets: ["SolitaireCore"]),
    ],
    targets: [
        .target(name: "SolitaireCore"),
        .testTarget(name: "SolitaireCoreTests", dependencies: ["SolitaireCore"]),
    ]
)
