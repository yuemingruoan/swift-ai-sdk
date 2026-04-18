import Foundation

public enum AgentStreamEvent: Codable, Equatable, Sendable {
    case textDelta(String)
    case turnCompleted(AgentTurn)
}

