import Foundation

public struct AgentConversationState: Codable, Equatable, Sendable {
    public var sessionID: String
    public var messages: [AgentMessage]
    public var continuation: [String: String]

    public init(
        sessionID: String,
        messages: [AgentMessage] = [],
        continuation: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.messages = messages
        self.continuation = continuation
    }

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
