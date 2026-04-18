import Testing
@testable import AgentCore

struct ToolRegistryTests {
    @Test func registry_resolves_local_and_remote_descriptors() async throws {
        let registry = ToolRegistry()

        try await registry.register(
            .local(name: "echo", input: EchoInput.self, output: EchoOutput.self)
        )
        try await registry.register(
            .remote(name: "search", transport: "mcp", inputSchema: .object(required: ["query"]))
        )

        #expect(await registry.descriptor(named: "echo") != nil)
        #expect(await registry.descriptor(named: "search") != nil)
    }
}

private struct EchoInput: Codable, Equatable, Sendable {
    var message: String
}

private struct EchoOutput: Codable, Equatable, Sendable {
    var echoed: String
}
