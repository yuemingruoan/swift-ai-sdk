import Foundation

/// A completed input/output exchange within a session.
public struct AgentTurn: Codable, Equatable, Sendable {
    public var sessionID: String
    public var input: [AgentMessage]
    public var output: [AgentMessage]
    /// Optional before persistence. Stores should materialize a non-nil value before replay.
    public var sequenceNumber: Int?

    /// Creates a persisted or in-flight turn value.
    /// - Parameters:
    ///   - sessionID: Identifier for the session that owns the turn.
    ///   - input: Input messages sent to the model for the turn.
    ///   - output: Output messages produced by the completed turn.
    ///   - sequenceNumber: Optional replay order. Stores typically materialize this before returning turns.
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
