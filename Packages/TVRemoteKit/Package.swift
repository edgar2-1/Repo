// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TVRemoteKit",
    platforms: [
        .watchOS(.v9),
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "TVRemoteCore", targets: ["TVRemoteCore"]),
        .library(name: "GoogleTVRemote", targets: ["GoogleTVRemote"]),
        .library(name: "RokuRemote", targets: ["RokuRemote"]),
        .library(name: "SamsungRemote", targets: ["SamsungRemote"]),
        .library(name: "LGRemote", targets: ["LGRemote"]),
    ],
    dependencies: [
        // RSA key generation, SHA-256 and X.509 self-signed certificate creation (Google TV).
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
    ],
    targets: [
        // Brand-neutral: controller protocol, universal keys, saved TVs,
        // keychain secrets, SSDP + subnet-scan discovery, HTTP/WebSocket helpers.
        .target(name: "TVRemoteCore"),

        // Android TV Remote v2 + Polo pairing (Chromecast with Google TV, Android TV 11+).
        .target(
            name: "GoogleTVRemote",
            dependencies: [
                "TVRemoteCore",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
            ]
        ),

        // Roku External Control Protocol (HTTP, port 8060).
        .target(name: "RokuRemote", dependencies: ["TVRemoteCore"]),

        // Samsung Tizen remote WebSocket (port 8002 / 8001).
        .target(name: "SamsungRemote", dependencies: ["TVRemoteCore"]),

        // LG webOS SSAP WebSocket (port 3000 / 3001).
        .target(name: "LGRemote", dependencies: ["TVRemoteCore"]),

        .testTarget(name: "TVRemoteCoreTests", dependencies: ["TVRemoteCore"]),
        .testTarget(name: "GoogleTVRemoteTests", dependencies: ["GoogleTVRemote"]),
        .testTarget(name: "RokuRemoteTests", dependencies: ["RokuRemote"]),
        .testTarget(name: "SamsungRemoteTests", dependencies: ["SamsungRemote"]),
        .testTarget(name: "LGRemoteTests", dependencies: ["LGRemote"]),
    ]
)
