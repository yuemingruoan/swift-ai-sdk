import Foundation

public struct AgentToolCall: Codable, Equatable, Sendable {
    public var callID: String?
    public var invocation: ToolInvocation

    public init(callID: String? = nil, invocation: ToolInvocation) {
        self.callID = callID
        self.invocation = invocation
    }
}
