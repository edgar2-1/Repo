// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RestockKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RestockKit", targets: ["RestockKit"]),
    ],
    targets: [
        .target(name: "RestockKit"),
        .testTarget(name: "RestockKitTests", dependencies: ["RestockKit"], resources: [.copy("Fixtures")]),
    ]
)
