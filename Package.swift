// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ow",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "ow",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            resources: [],
            linkerSettings: [
                .linkedFramework("Network"),
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "owTests",
            dependencies: ["ow"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
