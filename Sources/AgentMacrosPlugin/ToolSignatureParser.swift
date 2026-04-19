import SwiftSyntax

enum ToolSignatureParser {
    static func parseExplicitName(from attribute: AttributeSyntax) -> String? {
        guard
            case .argumentList(let arguments) = attribute.arguments,
            let firstArgument = arguments.first,
            let literal = firstArgument.expression.as(StringLiteralExprSyntax.self)
        else {
            return nil
        }

        return literal.segments.compactMap { segment in
            segment.as(StringSegmentSyntax.self)?.content.text
        }.joined()
    }

    static func defaultIdentifier(from declaration: some DeclGroupSyntax) -> String? {
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            return structDecl.name.text
        }
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return classDecl.name.text
        }
        if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            return actorDecl.name.text
        }
        if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            return enumDecl.name.text
        }
        return nil
    }
}
