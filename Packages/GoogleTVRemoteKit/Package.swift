// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GoogleTVRemoteKit",
    platforms: [
        .watchOS(.v9),
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "GoogleTVRemoteKit", targets: ["GoogleTVRemoteKit"]),
    ],
    dependencies: [
        // RSA key generation, SHA-256 and X.509 self-signed certificate creation.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "GoogleTVRemoteKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ]
        ),
        .testTarget(
            name: "GoogleTVRemoteKitTests",
            dependencies: ["GoogleTVRemoteKit"]
        ),
    ]
)
