import Foundation

public struct AgentTurn: Codable, Equatable, Sendable {
    public var sessionID: String
    public var input: [AgentMessage]
    public var output: [AgentMessage]

    public init(sessionID: String, input: [AgentMessage], output: [AgentMessage]) {
        self.sessionID = sessionID
        self.input = input
        self.output = output
    }
}

