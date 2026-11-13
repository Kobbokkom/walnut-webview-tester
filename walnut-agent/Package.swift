// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "walnut-agent",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "walnut-agent", targets: ["WalnutAgent"])],
    dependencies: [.package(path: "../WalnutPairing")],
    targets: [
        .executableTarget(name: "WalnutAgent", dependencies: ["WalnutPairing"]),
        .testTarget(name: "WalnutAgentTests", dependencies: ["WalnutAgent"])
    ]
)
