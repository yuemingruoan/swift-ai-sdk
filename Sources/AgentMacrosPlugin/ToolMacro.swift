import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct ToolMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let toolName = ToolSignatureParser.parseExplicitName(from: node)
            ?? ToolSignatureParser.defaultIdentifier(from: declaration)
            ?? "Tool"

        return [
            ToolDescriptorEmitter.descriptorMember(named: toolName),
        ]
    }
}

@main
struct AgentMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ToolMacro.self,
    ]
}
