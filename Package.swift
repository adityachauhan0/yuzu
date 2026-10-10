// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "YuzuHarness",
    platforms: [
        .macOS("26.4"),
    ],
    products: [
        .library(name: "YuzuHarness", targets: ["YuzuHarness"]),
        .library(name: "YuzuModel", targets: ["YuzuModel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/trymirai/uzu.git", from: "0.6.2"),
    ],
    targets: [
        .target(name: "YuzuHarness"),
        .target(
            name: "YuzuModel",
            dependencies: [
                "YuzuHarness",
                .product(name: "Uzu", package: "uzu"),
            ]
        ),
        .testTarget(
            name: "YuzuHarnessTests",
            dependencies: ["YuzuHarness"]
        ),
        .testTarget(
            name: "LiveUzuTests",
            dependencies: ["YuzuHarness", "YuzuModel"]
        ),
    ]
)
