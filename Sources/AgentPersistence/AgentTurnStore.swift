import AgentCore

public protocol AgentTurnStore: Sendable {
    func appendTurn(_ turn: AgentTurn) async throws
    /// Stores must materialize a unique, non-nil `sequenceNumber` for persisted turns.
    /// Returned turns are ordered by ascending `sequenceNumber`.
    func turns(forSessionID sessionID: String) async throws -> [AgentTurn]
    func deleteTurns(forSessionID sessionID: String) async throws
}
