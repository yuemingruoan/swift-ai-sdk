import AgentCore
import Foundation

public struct AgentSessionRecord: Codable, Equatable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct AgentTurnRecord: Codable, Equatable, Sendable {
    public let sessionID: String
    public let input: [AgentMessage]
    public let output: [AgentMessage]
    public let sequenceNumber: Int?

    public init(
        sessionID: String,
        input: [AgentMessage],
        output: [AgentMessage],
        sequenceNumber: Int? = nil
    ) {
        self.sessionID = sessionID
        self.input = input
        self.output = output
        self.sequenceNumber = sequenceNumber
    }
}
