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
        .library(name: "AgentOpenAI", targets: ["AgentOpenAI"]),
        .library(name: "AgentPersistence", targets: ["AgentPersistence"]),
        .library(name: "AgentMacros", targets: ["AgentMacros"]),
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
            name: "AgentOpenAI",
            dependencies: [
                "AgentCore",
            ],
            path: "Sources/AgentOpenAI"
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
        .executableTarget(
            name: "OpenAIResponsesExample",
            dependencies: [
                "AgentCore",
                "AgentOpenAI",
            ],
            path: "Examples/OpenAIResponsesExample"
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
