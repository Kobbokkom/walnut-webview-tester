// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "walnut-agent",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "walnut-agent", targets: ["WalnutAgent"])],
    targets: [
        .executableTarget(name: "WalnutAgent"),
        .testTarget(name: "WalnutAgentTests", dependencies: ["WalnutAgent"])
    ]
)
