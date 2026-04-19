import AgentCore

public actor InMemoryAgentStore: AgentSessionStore, AgentTurnStore {
    private var sessionsByID: [String: AgentSession]
    private var turnsBySessionID: [String: [AgentTurn]]

    public init() {
        self.sessionsByID = [:]
        self.turnsBySessionID = [:]
    }

    public func saveSession(_ session: AgentSession) async throws {
        sessionsByID[session.id] = session
    }

    public func session(id: String) async throws -> AgentSession? {
        sessionsByID[id]
    }

    /// Returns a stable, deterministic order for the in-memory implementation.
    public func listSessions() async throws -> [AgentSession] {
        sessionsByID.values.sorted { $0.id < $1.id }
    }

    public func deleteSession(id: String) async throws {
        sessionsByID.removeValue(forKey: id)
        turnsBySessionID.removeValue(forKey: id)
    }

    public func appendTurn(_ turn: AgentTurn) async throws {
        turnsBySessionID[turn.sessionID, default: []].append(turn)
    }

    /// Preserves append order for the in-memory implementation.
    public func turns(forSessionID sessionID: String) async throws -> [AgentTurn] {
        turnsBySessionID[sessionID] ?? []
    }

    public func deleteTurns(forSessionID sessionID: String) async throws {
        turnsBySessionID.removeValue(forKey: sessionID)
    }
}
