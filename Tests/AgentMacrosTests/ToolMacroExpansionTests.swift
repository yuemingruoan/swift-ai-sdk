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

    @Test
    func tool_macro_defaults_to_decl_name_when_argument_is_omitted() {
        assertMacroExpansion(
            """
            @Tool
            struct EchoTool {
                func callAsFunction(input: EchoInput) async throws -> EchoOutput {}
            }
            """,
            expandedSource: """
            struct EchoTool {
                func callAsFunction(input: EchoInput) async throws -> EchoOutput {}
                static let toolDescriptor = ToolDescriptor(name: "EchoTool", executionKind: .local)
            }
            """,
            macros: ["Tool": ToolMacro.self]
        )
    }

    @Test
    func tool_macro_reports_diagnostic_when_name_cannot_be_derived() {
        assertMacroExpansion(
            """
            @Tool
            extension EchoTool {}
            """,
            expandedSource: """
            extension EchoTool {}
            """,
            diagnostics: [
                .init(
                    message: ToolMacroDiagnostic.missingToolName.message,
                    line: 1,
                    column: 1
                )
            ],
            macros: ["Tool": ToolMacro.self]
        )
    }
}
