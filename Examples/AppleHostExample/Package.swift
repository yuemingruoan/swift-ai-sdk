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
                .product(name: "AgentCore", package: "swift-ai-sdk"),
                .product(name: "AgentOpenAI", package: "swift-ai-sdk"),
                .product(name: "AgentOpenAIAuth", package: "swift-ai-sdk"),
                .product(name: "AgentOpenAIAuthApple", package: "swift-ai-sdk"),
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
                .product(name: "AgentCore", package: "swift-ai-sdk"),
                .product(name: "AgentPersistence", package: "swift-ai-sdk"),
                .product(name: "AgentOpenAIAuthApple", package: "swift-ai-sdk"),
            ]
        ),
    ]
)
