import Foundation

public protocol RemoteToolTransport: Sendable {
    var transportID: String { get }
    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult
}
