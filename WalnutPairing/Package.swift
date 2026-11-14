// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WalnutPairing",
    platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [.library(name: "WalnutPairing", targets: ["WalnutPairing"])],
    targets: [
        .target(name: "WalnutPairing"),
        .testTarget(name: "WalnutPairingTests", dependencies: ["WalnutPairing"]),
    ]
)
