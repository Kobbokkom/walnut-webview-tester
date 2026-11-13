// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WalnutPairing",
    platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [.library(name: "WalnutPairing", targets: ["WalnutPairing"])],
    dependencies: [
        .package(url: "https://github.com/firebase/boringSSL-SwiftPM.git", exact: "0.41.0"),
    ],
    targets: [
        .target(name: "WalnutSPAKE2", dependencies: [
            .product(name: "openssl_grpc", package: "boringSSL-SwiftPM"),
        ]),
        .target(
            name: "WalnutPairing",
            dependencies: ["WalnutSPAKE2"],
            resources: [.copy("Resources/BoringSSL-LICENSE.txt")]
        ),
        .testTarget(name: "WalnutPairingTests", dependencies: ["WalnutPairing"]),
    ],
    cxxLanguageStandard: .cxx17
)
