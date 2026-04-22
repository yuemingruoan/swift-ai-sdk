// swift-tools-version: 6.0

import CompilerPluginSupport
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
        .library(name: "AnthropicMessagesAPI", targets: ["AnthropicMessagesAPI"]),
        .library(name: "AnthropicAgentRuntime", targets: ["AnthropicAgentRuntime"]),
        .library(name: "OpenAIResponsesAPI", targets: ["OpenAIResponsesAPI"]),
        .library(name: "OpenAIAgentRuntime", targets: ["OpenAIAgentRuntime"]),
        .library(name: "OpenAIAuthentication", targets: ["OpenAIAuthentication"]),
        .library(name: "OpenAIAppleAuthentication", targets: ["OpenAIAppleAuthentication"]),
        .library(name: "AgentPersistence", targets: ["AgentPersistence"]),
        .library(name: "AgentMacros", targets: ["AgentMacros"]),
        .executable(name: "OpenAIToolLoopExample", targets: ["OpenAIToolLoopExample"]),
        .executable(name: "AnthropicToolLoopExample", targets: ["AnthropicToolLoopExample"]),
        .executable(name: "SessionRunnerExample", targets: ["SessionRunnerExample"]),
        .executable(name: "PersistenceExample", targets: ["PersistenceExample"]),
        .executable(name: "OpenAIResponsesExample", targets: ["OpenAIResponsesExample"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .target(
            name: "AgentCore",
            path: "Sources/AgentCore"
        ),
        .target(
            name: "AgentPersistence",
            dependencies: [
                "AgentCore",
            ],
            path: "Sources/AgentPersistence"
        ),
        .target(
            name: "AnthropicMessagesAPI",
            dependencies: [
                "AgentCore",
            ],
            path: "Sources/AgentAnthropic/API"
        ),
        .target(
            name: "AnthropicAgentRuntime",
            dependencies: [
                "AgentCore",
                "AnthropicMessagesAPI",
            ],
            path: "Sources/AgentAnthropic/Runtime"
        ),
        .target(
            name: "OpenAIResponsesAPI",
            dependencies: [
                "AgentCore",
            ],
            path: "Sources/AgentOpenAI/API"
        ),
        .target(
            name: "OpenAIAgentRuntime",
            dependencies: [
                "AgentCore",
                "OpenAIResponsesAPI",
            ],
            path: "Sources/AgentOpenAI/Runtime"
        ),
        .target(
            name: "OpenAIAuthentication",
            dependencies: [
                "AgentCore",
                "OpenAIResponsesAPI",
            ],
            path: "Sources/AgentOpenAIAuth"
        ),
        .target(
            name: "OpenAIAppleAuthentication",
            dependencies: [
                "OpenAIAuthentication",
            ],
            path: "Sources/AgentOpenAIAuthApple"
        ),
        .macro(
            name: "AgentMacrosPlugin",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ],
            path: "Sources/AgentMacrosPlugin"
        ),
        .target(
            name: "AgentMacros",
            dependencies: [
                "AgentCore",
                "AgentMacrosPlugin",
            ],
            path: "Sources/AgentMacros"
        ),
        .target(
            name: "ExampleSupport",
            dependencies: [
                "OpenAIAgentRuntime",
            ],
            path: "Examples/ExampleSupport"
        ),
        .executableTarget(
            name: "OpenAIResponsesExample",
            dependencies: [
                "OpenAIAgentRuntime",
                "OpenAIResponsesAPI",
                "OpenAIAuthentication",
                "ExampleSupport",
            ],
            path: "Examples/OpenAIResponsesExample"
        ),
        .executableTarget(
            name: "OpenAIToolLoopExample",
            dependencies: [
                "OpenAIAgentRuntime",
                "OpenAIResponsesAPI",
                "OpenAIAuthentication",
                "ExampleSupport",
            ],
            path: "Examples/OpenAIToolLoopExample"
        ),
        .executableTarget(
            name: "AnthropicToolLoopExample",
            dependencies: [
                "AnthropicAgentRuntime",
                "AnthropicMessagesAPI",
                "ExampleSupport",
            ],
            path: "Examples/AnthropicToolLoopExample"
        ),
        .executableTarget(
            name: "SessionRunnerExample",
            dependencies: [
                "OpenAIAgentRuntime",
                "ExampleSupport",
            ],
            path: "Examples/SessionRunnerExample"
        ),
        .executableTarget(
            name: "PersistenceExample",
            dependencies: [
                "AgentPersistence",
                "ExampleSupport",
            ],
            path: "Examples/PersistenceExample"
        ),
        .testTarget(
            name: "AgentCoreTests",
            dependencies: [
                "AgentCore",
                "AgentPersistence",
            ],
            path: "Tests/AgentCoreTests"
        ),
        .testTarget(
            name: "AgentPersistenceTests",
            dependencies: [
                "AgentPersistence",
                "AgentCore",
            ],
            path: "Tests/AgentPersistenceTests"
        ),
        .testTarget(
            name: "AgentAnthropicTests",
            dependencies: [
                "AnthropicMessagesAPI",
                "AnthropicAgentRuntime",
                "AgentCore",
            ],
            path: "Tests/AgentAnthropicTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "AgentOpenAIAuthTests",
            dependencies: [
                "OpenAIAuthentication",
                "OpenAIResponsesAPI",
                "AgentCore",
            ],
            path: "Tests/AgentOpenAIAuthTests"
        ),
        .testTarget(
            name: "AgentOpenAIAuthAppleTests",
            dependencies: [
                "OpenAIAppleAuthentication",
                "OpenAIAuthentication",
            ],
            path: "Tests/AgentOpenAIAuthAppleTests"
        ),
        .testTarget(
            name: "AgentOpenAITests",
            dependencies: [
                "OpenAIResponsesAPI",
                "OpenAIAgentRuntime",
                "AgentCore",
            ],
            path: "Tests/AgentOpenAITests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "AgentMacrosTests",
            dependencies: [
                "AgentMacros",
                "AgentMacrosPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/AgentMacrosTests"
        ),
    ]
)
