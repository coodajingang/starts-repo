// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CloudPlayer",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "CloudPlayer",
            targets: ["CloudPlayer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.0"),
    ],
    targets: [
        .target(
            name: "CloudPlayer",
            dependencies: [
                "KeychainAccess",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "CloudPlayerTests",
            dependencies: ["CloudPlayer"]
        ),
    ]
)