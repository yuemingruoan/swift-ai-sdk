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
        .library(name: "AgentCore", targets: ["AgentCore"]),
        .library(name: "AgentAnthropic", targets: ["AgentAnthropic"]),
        .library(name: "AgentOpenAI", targets: ["AgentOpenAI"]),
        .library(name: "AgentOpenAIAuth", targets: ["AgentOpenAIAuth"]),
        .library(name: "AgentOpenAIAuthApple", targets: ["AgentOpenAIAuthApple"]),
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
            name: "AgentAnthropic",
            dependencies: [
                "AgentCore",
            ],
            path: "Sources/AgentAnthropic"
        ),
        .target(
            name: "AgentOpenAI",
            dependencies: [
                "AgentCore",
            ],
            path: "Sources/AgentOpenAI"
        ),
        .target(
            name: "AgentOpenAIAuth",
            dependencies: [
                "AgentOpenAI",
                "AgentCore",
            ],
            path: "Sources/AgentOpenAIAuth"
        ),
        .target(
            name: "AgentOpenAIAuthApple",
            dependencies: [
                "AgentOpenAIAuth",
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
                "AgentCore",
            ],
            path: "Examples/ExampleSupport"
        ),
        .executableTarget(
            name: "OpenAIResponsesExample",
            dependencies: [
                "AgentCore",
                "AgentOpenAI",
                "AgentOpenAIAuth",
                "ExampleSupport",
            ],
            path: "Examples/OpenAIResponsesExample"
        ),
        .executableTarget(
            name: "OpenAIToolLoopExample",
            dependencies: [
                "AgentCore",
                "AgentOpenAI",
                "AgentOpenAIAuth",
                "ExampleSupport",
            ],
            path: "Examples/OpenAIToolLoopExample"
        ),
        .executableTarget(
            name: "AnthropicToolLoopExample",
            dependencies: [
                "AgentCore",
                "AgentAnthropic",
                "ExampleSupport",
            ],
            path: "Examples/AnthropicToolLoopExample"
        ),
        .executableTarget(
            name: "SessionRunnerExample",
            dependencies: [
                "AgentCore",
                "ExampleSupport",
            ],
            path: "Examples/SessionRunnerExample"
        ),
        .executableTarget(
            name: "PersistenceExample",
            dependencies: [
                "AgentCore",
                "AgentPersistence",
                "ExampleSupport",
            ],
            path: "Examples/PersistenceExample"
        ),
        .testTarget(
            name: "AgentCoreTests",
            dependencies: [
                "AgentCore",
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
                "AgentAnthropic",
                "AgentCore",
            ],
            path: "Tests/AgentAnthropicTests"
        ),
        .testTarget(
            name: "AgentOpenAIAuthTests",
            dependencies: [
                "AgentOpenAIAuth",
                "AgentOpenAI",
                "AgentCore",
            ],
            path: "Tests/AgentOpenAIAuthTests"
        ),
        .testTarget(
            name: "AgentOpenAIAuthAppleTests",
            dependencies: [
                "AgentOpenAIAuthApple",
                "AgentOpenAIAuth",
            ],
            path: "Tests/AgentOpenAIAuthAppleTests"
        ),
        .testTarget(
            name: "AgentOpenAITests",
            dependencies: [
                "AgentOpenAI",
                "AgentCore",
            ],
            path: "Tests/AgentOpenAITests"
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
