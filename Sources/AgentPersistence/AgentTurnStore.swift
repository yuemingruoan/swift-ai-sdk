import AgentCore

public protocol AgentTurnStore: Sendable {
    func appendTurn(_ turn: AgentTurn) async throws
    /// Returns turns in ascending `sequenceNumber` order.
    func turns(forSessionID sessionID: String) async throws -> [AgentTurn]
    func deleteTurns(forSessionID sessionID: String) async throws
}
