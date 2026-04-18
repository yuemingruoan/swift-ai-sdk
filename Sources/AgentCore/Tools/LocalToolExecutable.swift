import Foundation

public protocol LocalToolExecutable: Sendable {
    var descriptor: ToolDescriptor { get }
    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult
}
