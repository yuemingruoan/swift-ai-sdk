import Testing
@testable import AgentCore

struct ToolExecutorMiddlewareTests {
    @Test func middleware_allows_local_tool_execution() async throws {
        let middleware = AgentMiddlewareStack(
            toolAuthorization: [AllowingMiddleware()],
            audit: [AuditRecorderMiddleware()]
        )
        let executable = RecordingMiddlewareLocalExecutable()
        let executor = ToolExecutor(middleware: middleware)
        try await executor.register(executable)

        let result = try await executor.invoke(
            ToolInvocation(toolName: "echo", arguments: ["message": .string("swift")])
        )

        #expect(result == ToolResult(payload: .string("swift")))
        #expect(await executable.recordedInvocations.count == 1)
    }

    @Test func middleware_allows_remote_tool_execution() async throws {
        let registry = ToolRegistry()
        try await registry.register(
            .remote(
                name: "search",
                transport: "mcp",
                inputSchema: .object(required: ["query"])
            )
        )
        let transport = RecordingMiddlewareRemoteTransport()
        let executor = ToolExecutor(
            registry: registry,
            middleware: AgentMiddlewareStack(toolAuthorization: [AllowingMiddleware()])
        )
        await executor.register(transport)

        let result = try await executor.invoke(
            ToolInvocation(toolName: "search", arguments: ["query": .string("swift")])
        )

        #expect(result == ToolResult(payload: .object(["transport": .string("mcp")])))
        #expect(await transport.recordedInvocations.count == 1)
    }

    @Test func middleware_denies_local_tool_before_execution() async throws {
        let executable = RecordingMiddlewareLocalExecutable()
        let executor = ToolExecutor(
            middleware: AgentMiddlewareStack(
                toolAuthorization: [DenyingMiddleware(reason: "blocked")]
            )
        )
        try await executor.register(executable)

        await #expect(throws: AgentRuntimeError.toolCallDenied(toolName: "echo", reason: "blocked")) {
            _ = try await executor.invoke(
                ToolInvocation(toolName: "echo", arguments: ["message": .string("swift")])
            )
        }

        #expect(await executable.recordedInvocations.isEmpty)
    }

    @Test func middleware_denies_remote_tool_before_execution() async throws {
        let registry = ToolRegistry()
        try await registry.register(
            .remote(
                name: "search",
                transport: "mcp",
                inputSchema: .object(required: ["query"])
            )
        )
        let transport = RecordingMiddlewareRemoteTransport()
        let executor = ToolExecutor(
            registry: registry,
            middleware: AgentMiddlewareStack(
                toolAuthorization: [DenyingMiddleware(reason: "blocked")]
            )
        )
        await executor.register(transport)

        await #expect(throws: AgentRuntimeError.toolCallDenied(toolName: "search", reason: "blocked")) {
            _ = try await executor.invoke(
                ToolInvocation(toolName: "search", arguments: ["query": .string("swift")])
            )
        }

        #expect(await transport.recordedInvocations.isEmpty)
    }

    @Test func hooks_still_observe_allowed_execution() async throws {
        let hook = MiddlewareRecordingHook()
        let executable = RecordingMiddlewareLocalExecutable()
        let executor = ToolExecutor(
            middleware: AgentMiddlewareStack(toolAuthorization: [AllowingMiddleware()]),
            hooks: [hook]
        )
        try await executor.register(executable)

        _ = try await executor.invoke(
            ToolInvocation(toolName: "echo", arguments: ["message": .string("swift")])
        )

        #expect(await hook.recordedEvents == [
            .willInvoke(toolName: "echo"),
            .didInvoke(toolName: "echo", payload: .string("swift")),
        ])
    }
}

private struct AllowingMiddleware: AgentToolAuthorizationMiddleware {}

private struct DenyingMiddleware: AgentToolAuthorizationMiddleware {
    let reason: String

    func authorize(_ context: AgentToolInvocationContext) async throws -> AgentToolAuthorizationDecision {
        .deny(reason: reason)
    }
}

private struct AuditRecorderMiddleware: AgentAuditMiddleware {}

private final class MiddlewareRecordingHook: ToolExecutorHook, @unchecked Sendable {
    private let recorder = MiddlewareHookRecorder()

    var recordedEvents: [MiddlewareHookEvent] {
        get async { await recorder.events }
    }

    func willInvoke(descriptor: ToolDescriptor, invocation: ToolInvocation) async {
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

private enum MiddlewareHookEvent: Equatable, Sendable {
    case willInvoke(toolName: String)
    case didInvoke(toolName: String, payload: ToolValue)
    case didFail(toolName: String, errorType: String, message: String)
}

private actor MiddlewareHookRecorder {
    private var storedEvents: [MiddlewareHookEvent] = []

    var events: [MiddlewareHookEvent] {
        storedEvents
    }

    func append(_ event: MiddlewareHookEvent) {
        storedEvents.append(event)
    }
}

private actor RecordingMiddlewareLocalExecutable: LocalToolExecutable {
    let descriptor = ToolDescriptor.local(
        name: "echo",
        input: String.self,
        output: String.self
    )

    private var invocations: [ToolInvocation] = []

    var recordedInvocations: [ToolInvocation] {
        invocations
    }

    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        invocations.append(invocation)
        return ToolResult(payload: invocation.arguments?["message"] ?? .null)
    }
}

private actor RecordingMiddlewareRemoteTransport: RemoteToolTransport {
    let transportID = "mcp"
    private var invocations: [ToolInvocation] = []

    var recordedInvocations: [ToolInvocation] {
        invocations
    }

    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        invocations.append(invocation)
        return ToolResult(payload: .object(["transport": .string(transportID)]))
    }
}
