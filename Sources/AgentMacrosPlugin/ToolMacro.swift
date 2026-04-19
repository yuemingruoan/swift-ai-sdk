import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public enum ToolMacroDiagnostic: DiagnosticMessage {
    case missingToolName

    public var message: String {
        switch self {
        case .missingToolName:
            "@Tool requires an explicit string argument or a named type declaration"
        }
    }

    public var diagnosticID: MessageID {
        switch self {
        case .missingToolName:
            MessageID(domain: "ToolMacroDiagnostic", id: "missingToolName")
        }
    }

    public var severity: DiagnosticSeverity {
        .error
    }

    func diagnose(at node: Syntax) -> Diagnostic {
        Diagnostic(node: node, message: self)
    }
}

public struct ToolMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let toolName = ToolSignatureParser.parseExplicitName(from: node)
            ?? ToolSignatureParser.defaultIdentifier(from: declaration)
        guard let toolName else {
            context.diagnose(ToolMacroDiagnostic.missingToolName.diagnose(at: Syntax(declaration)))
            return []
        }

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
