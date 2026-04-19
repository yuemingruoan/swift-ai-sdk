import Foundation

public enum AgentStreamEvent: Codable, Equatable, Sendable {
    case textDelta(String)
    case toolCall(AgentToolCall)
    case messagesCompleted([AgentMessage])
    case turnCompleted(AgentTurn)
}
