import AgentCore

public protocol AgentTurnStore: Sendable {
    func appendTurn(_ turn: AgentTurn) async throws
    /// Collection ordering is implementation-defined.
    func turns(forSessionID sessionID: String) async throws -> [AgentTurn]
    func deleteTurns(forSessionID sessionID: String) async throws
}
