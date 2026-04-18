import Testing
@testable import AgentCore

struct RemoteToolExecutorTests {
    @Test func executor_routes_remote_invocation_through_matching_transport() async throws {
        let registry = ToolRegistry()
        try await registry.register(
            .remote(name: "search", transport: "mcp", inputSchema: .object(required: ["query"]))
        )

        let transport = RecordingRemoteTransport()
        let executor = ToolExecutor(registry: registry)
        await executor.register(transport)

        let invocation = ToolInvocation(
            toolName: "search",
            arguments: ["query": .string("swift")]
        )

        let result = try await executor.invoke(invocation)

        #expect(result == ToolResult(payload: .object(["transport": .string("mcp")])))
        #expect(await transport.recordedInvocations == [invocation])
    }

    @Test func executor_throws_when_remote_transport_is_missing() async throws {
        let registry = ToolRegistry()
        try await registry.register(
            .remote(name: "search", transport: "mcp", inputSchema: .object(required: ["query"]))
        )

        let executor = ToolExecutor(registry: registry)
        let invocation = ToolInvocation(
            toolName: "search",
            arguments: ["query": .string("swift")]
        )

        do {
            _ = try await executor.invoke(invocation)
            Issue.record("Expected missing remote transport error")
        } catch let error as ToolExecutorError {
            #expect(error == .missingRemoteTransport(id: "mcp"))
        }
    }
}

private actor RecordingRemoteTransport: RemoteToolTransport {
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
