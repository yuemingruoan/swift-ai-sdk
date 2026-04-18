import Testing
@testable import AgentCore

struct LocalToolExecutorTests {
    @Test func executor_routes_local_invocation_through_matching_executable() async throws {
        let executable = RecordingLocalExecutable()
        let executor = ToolExecutor()
        try await executor.register(executable)

        let invocation = ToolInvocation(
            toolName: "echo",
            input: .string("swift")
        )

        let result = try await executor.invoke(invocation)

        #expect(result == ToolResult(payload: .string("swift")))
        #expect(await executable.recordedInvocations == [invocation])
    }
}

private actor RecordingLocalExecutable: LocalToolExecutable {
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
        return ToolResult(payload: invocation.input)
    }
}
