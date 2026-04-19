import SwiftSyntax

enum ToolSignatureParser {
    enum ExplicitNameParseResult: Equatable {
        case missing
        case valid(String)
        case invalid
    }

    static func parseExplicitName(from attribute: AttributeSyntax) -> ExplicitNameParseResult {
        guard case .argumentList(let arguments) = attribute.arguments else {
            return .missing
        }
        guard let firstArgument = arguments.first else {
            return .missing
        }
        guard arguments.count == 1 else {
            return .invalid
        }
        guard let literal = firstArgument.expression.as(StringLiteralExprSyntax.self) else {
            return .invalid
        }

        let segments = literal.segments.compactMap { segment in
            segment.as(StringSegmentSyntax.self)?.content.text
        }
        guard segments.count == literal.segments.count else {
            return .invalid
        }

        return .valid(segments.joined())
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
