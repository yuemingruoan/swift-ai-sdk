// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppleHostExampleProject",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "AppleHostExample", targets: ["AppleHostExample"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "AppleHostExampleSupport",
            dependencies: [
                .product(name: "OpenAIAgentRuntime", package: "swift-ai-sdk"),
                .product(name: "OpenAIAuthentication", package: "swift-ai-sdk"),
                .product(name: "OpenAIAppleAuthentication", package: "swift-ai-sdk"),
                .product(name: "AgentPersistence", package: "swift-ai-sdk"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "AppleHostExample",
            dependencies: [
                "AppleHostExampleSupport",
            ]
        ),
        .testTarget(
            name: "AppleHostExampleSupportTests",
            dependencies: [
                "AppleHostExampleSupport",
                .product(name: "AgentPersistence", package: "swift-ai-sdk"),
                .product(name: "OpenAIAppleAuthentication", package: "swift-ai-sdk"),
            ]
        ),
    ]
)
