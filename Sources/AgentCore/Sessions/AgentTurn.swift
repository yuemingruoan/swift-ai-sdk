import Foundation

public struct AgentTurn: Codable, Equatable, Sendable {
    public var sessionID: String
    public var input: [AgentMessage]
    public var output: [AgentMessage]
    /// Optional before persistence. Stores should materialize a non-nil value before replay.
    public var sequenceNumber: Int?

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
