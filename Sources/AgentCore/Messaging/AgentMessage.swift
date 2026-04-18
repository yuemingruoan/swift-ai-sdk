import Foundation

public enum AgentMessageRole: String, Codable, Sendable {
    case system
    case developer
    case user
    case assistant
    case tool
}

public struct AgentMessage: Codable, Equatable, Sendable {
    public var role: AgentMessageRole
    public var parts: [MessagePart]

    public init(role: AgentMessageRole, parts: [MessagePart]) {
        self.role = role
        self.parts = parts
    }
}

public extension AgentMessage {
    static func userText(_ text: String) -> Self {
        Self(role: .user, parts: [.text(text)])
    }
}

