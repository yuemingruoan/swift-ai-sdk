import Foundation

public struct AgentRunContext: Codable, Equatable, Sendable {
    public var session: AgentSession
    public var conversation: AgentConversationState

    public init(
        session: AgentSession,
        conversation: AgentConversationState? = nil
    ) {
        self.session = session
        self.conversation = conversation ?? AgentConversationState(sessionID: session.id)
    }
}
