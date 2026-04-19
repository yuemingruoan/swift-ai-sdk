import AgentCore

public protocol AgentTurnStore: Sendable {
    func appendTurn(_ turn: AgentTurn) async throws
    func turns(forSessionID sessionID: String) async -> [AgentTurn]
    func deleteTurns(forSessionID sessionID: String) async throws
}
