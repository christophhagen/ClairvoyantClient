// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "ClairvoyantClient",
    platforms: [.macOS(.v12), .iOS(.v14), .watchOS(.v9)],
    products: [
        .library(
            name: "ClairvoyantClient",
            targets: ["ClairvoyantClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/christophhagen/Clairvoyant", from: "0.14.2"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ClairvoyantClient",
            dependencies: ["Clairvoyant"]),
        .testTarget(
            name: "ClairvoyantClientTests",
            dependencies: ["ClairvoyantClient"]),
    ]
)
