import SwiftSyntaxMacrosTestSupport
import Testing
import AgentMacros
import AgentMacrosPlugin

struct ToolMacroExpansionTests {
    @Test
    func tool_macro_emits_descriptor_member() {
        assertMacroExpansion(
            """
            @Tool("echo")
            struct EchoTool {
                func callAsFunction(input: EchoInput) async throws -> EchoOutput {}
            }
            """,
            expandedSource: """
            struct EchoTool {
                func callAsFunction(input: EchoInput) async throws -> EchoOutput {}
                static let toolDescriptor = ToolDescriptor(name: "echo", executionKind: .local)
            }
            """,
            macros: ["Tool": ToolMacro.self]
        )
    }
}
