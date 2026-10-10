// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "YuzuHarness",
    platforms: [
        .macOS("26.4"),
    ],
    products: [
        .library(name: "YuzuHarness", targets: ["YuzuHarness"]),
    ],
    targets: [
        .target(name: "YuzuHarness"),
        .testTarget(
            name: "YuzuHarnessTests",
            dependencies: ["YuzuHarness"]
        ),
    ]
)
