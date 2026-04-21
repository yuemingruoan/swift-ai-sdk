import Foundation

/// Stable identity for a conversation session.
public struct AgentSession: Codable, Equatable, Sendable {
    public var id: String

    /// Creates a session identity value.
    /// - Parameter id: Stable identifier for the session.
    public init(id: String) {
        self.id = id
    }
}
