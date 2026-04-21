import Foundation

/// Canonical message roles shared across provider adapters.
public enum AgentMessageRole: String, Codable, Sendable {
    case system
    case developer
    case user
    case assistant
    case tool
}

/// A provider-neutral message composed of structured parts.
public struct AgentMessage: Codable, Equatable, Sendable {
    public var role: AgentMessageRole
    public var parts: [MessagePart]

    /// Creates a provider-neutral message from a role and ordered content parts.
    /// - Parameters:
    ///   - role: Semantic role associated with the message.
    ///   - parts: Ordered content parts carried by the message.
    public init(role: AgentMessageRole, parts: [MessagePart]) {
        self.role = role
        self.parts = parts
    }
}

public extension AgentMessage {
    /// Creates a single text message from the user role.
    /// - Parameter text: Text to place in the message body.
    /// - Returns: A user message containing one `.text` part.
    static func userText(_ text: String) -> Self {
        Self(role: .user, parts: [.text(text)])
    }
}
