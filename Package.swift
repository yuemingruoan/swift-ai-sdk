// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftAISDK",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "AgentCore", targets: ["AgentCore"]),
    ],
    targets: [
        .target(
            name: "AgentCore",
            path: "Sources/AgentCore"
        ),
        .testTarget(
            name: "AgentCoreTests",
            dependencies: [
                "AgentCore",
            ],
            path: "Tests/AgentCoreTests"
        ),
    ]
)
