import SwiftSyntax
import SwiftSyntaxBuilder

enum ToolDescriptorEmitter {
    static func descriptorMember(named toolName: String) -> DeclSyntax {
        """
        static let toolDescriptor = ToolDescriptor(name: "\(literal: toolName)", executionKind: .local)
        """
    }
}
