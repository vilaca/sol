// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SolitaireCore",
    // iOS 15 runs on iPhone 6s / SE (1st gen) and every later model.
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "SolitaireCore", targets: ["SolitaireCore"]),
    ],
    targets: [
        .target(name: "SolitaireCore"),
        .testTarget(name: "SolitaireCoreTests", dependencies: ["SolitaireCore"]),
    ]
)
