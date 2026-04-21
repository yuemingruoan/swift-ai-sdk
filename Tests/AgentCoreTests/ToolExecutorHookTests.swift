import Foundation
import Testing
@testable import AgentCore

struct ToolExecutorHookTests {
    @Test func hooks_observe_local_tool_success() async throws {
        let hook = RecordingHook()
        let executable = HookedLocalExecutable()
        let executor = ToolExecutor(hooks: [hook])
        try await executor.register(executable)

        let invocation = ToolInvocation(
            toolName: "echo",
            arguments: ["message": .string("swift")]
        )

        let result = try await executor.invoke(invocation)

        #expect(result == ToolResult(payload: .string("swift")))
        #expect(await hook.recordedEvents == [
            .willInvoke(toolName: "echo"),
            .didInvoke(toolName: "echo", payload: .string("swift")),
        ])
    }

    @Test func hooks_observe_remote_tool_success() async throws {
        let registry = ToolRegistry()
        try await registry.register(
            .remote(
                name: "search",
                transport: "mcp",
                inputSchema: ToolInputSchema.object(
                    properties: ["query": ToolInputSchema.string],
                    required: ["query"]
                ),
                description: "Searches remote index",
                outputSchema: ToolInputSchema.array(items: ToolInputSchema.string)
            )
        )

        let hook = RecordingHook()
        let transport = HookedRemoteTransport()
        let executor = ToolExecutor(registry: registry, hooks: [hook])
        await executor.register(transport)

        let invocation = ToolInvocation(
            toolName: "search",
            arguments: ["query": .string("swift")]
        )

        let result = try await executor.invoke(invocation)

        #expect(result == ToolResult(payload: .array([.string("swift"), .string("sdk")])))
        #expect(await hook.recordedEvents == [
            .willInvoke(toolName: "search"),
            .didInvoke(toolName: "search", payload: .array([.string("swift"), .string("sdk")])),
        ])
    }

    @Test func hooks_observe_failed_tool_execution() async throws {
        let hook = RecordingHook()
        let executable = FailingLocalExecutable()
        let executor = ToolExecutor(hooks: [hook])
        try await executor.register(executable)

        let invocation = ToolInvocation(
            toolName: "fail",
            arguments: ["message": .string("swift")]
        )

        do {
            _ = try await executor.invoke(invocation)
            Issue.record("Expected failing tool execution")
        } catch let error as FailingHookTestError {
            #expect(error == .boom)
        }

        #expect(await hook.recordedEvents == [
            .willInvoke(toolName: "fail"),
            .didFail(toolName: "fail", errorType: "FailingHookTestError", message: "boom"),
        ])
    }
}

private final class RecordingHook: ToolExecutorHook, @unchecked Sendable {
    private let recorder = HookEventRecorder()

    var recordedEvents: [HookEvent] {
        get async {
            await recorder.events
        }
    }

    func willInvoke(
        descriptor: ToolDescriptor,
        invocation: ToolInvocation
    ) async {
        await recorder.append(.willInvoke(toolName: descriptor.name))
    }

    func didInvoke(
        descriptor: ToolDescriptor,
        invocation: ToolInvocation,
        result: ToolResult
    ) async {
        await recorder.append(.didInvoke(toolName: descriptor.name, payload: result.payload))
    }

    func didFail(
        descriptor: ToolDescriptor,
        invocation: ToolInvocation,
        failure: ToolExecutorInvocationFailure
    ) async {
        await recorder.append(
            .didFail(
                toolName: descriptor.name,
                errorType: failure.errorType,
                message: failure.message
            )
        )
    }
}

private enum HookEvent: Equatable, Sendable {
    case willInvoke(toolName: String)
    case didInvoke(toolName: String, payload: ToolValue)
    case didFail(toolName: String, errorType: String, message: String)
}

private actor HookEventRecorder {
    private var storedEvents: [HookEvent] = []

    var events: [HookEvent] {
        storedEvents
    }

    func append(_ event: HookEvent) {
        storedEvents.append(event)
    }
}

private final class HookedLocalExecutable: LocalToolExecutable, @unchecked Sendable {
    let descriptor = ToolDescriptor.local(
        name: "echo",
        input: HookInput.self,
        output: String.self,
        description: "Echoes text",
        outputSchema: ToolInputSchema.string
    )

    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        let message = invocation.arguments?["message"] ?? .null
        return ToolResult(payload: message)
    }
}

private final class HookedRemoteTransport: RemoteToolTransport, @unchecked Sendable {
    let transportID = "mcp"

    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        ToolResult(payload: .array([.string("swift"), .string("sdk")]))
    }
}

private final class FailingLocalExecutable: LocalToolExecutable, @unchecked Sendable {
    let descriptor = ToolDescriptor.local(
        name: "fail",
        input: HookInput.self,
        output: String.self,
        description: "Always fails"
    )

    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        throw FailingHookTestError.boom
    }
}

private struct HookInput: Codable, Equatable, Sendable {
    let message: String
}

private enum FailingHookTestError: String, Error, Equatable, Sendable, LocalizedError {
    case boom

    var errorDescription: String? {
        rawValue
    }
}
