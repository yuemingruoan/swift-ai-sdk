import Foundation

/// Provider-neutral multi-turn state that can be replayed into the next request.
public struct AgentConversationState: Codable, Equatable, Sendable {
    public var sessionID: String
    public var messages: [AgentMessage]
    public var continuation: [String: String]

    /// Creates replayable multi-turn state for a logical session.
    /// - Parameters:
    ///   - sessionID: Stable identifier used to associate future turns with the same conversation.
    ///   - messages: Existing provider-neutral history to replay into the next turn.
    ///   - continuation: Provider-specific continuation metadata such as response identifiers.
    public init(
        sessionID: String,
        messages: [AgentMessage] = [],
        continuation: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.messages = messages
        self.continuation = continuation
    }

    /// Appends a completed turn to the stored message history.
    /// - Parameters:
    ///   - input: Input messages sent for the turn being recorded.
    ///   - output: Output messages produced by the completed turn.
    /// - Returns: A new conversation state with the additional turn appended.
    public func appendingTurn(
        input: [AgentMessage],
        output: [AgentMessage]
    ) -> Self {
        Self(
            sessionID: sessionID,
            messages: messages + input + output,
            continuation: continuation
        )
    }
}
