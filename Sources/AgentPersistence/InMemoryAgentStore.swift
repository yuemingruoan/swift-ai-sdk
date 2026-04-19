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
        let storedTurn = turn.withSequenceNumber(
            normalizedSequenceNumber(for: turn)
        )
        turnsBySessionID[turn.sessionID, default: []].append(storedTurn)
    }

    /// Preserves append order by returning turns sorted by `sequenceNumber`.
    public func turns(forSessionID sessionID: String) async throws -> [AgentTurn] {
        turnsBySessionID[sessionID]?.sorted(by: compareTurns) ?? []
    }

    public func deleteTurns(forSessionID sessionID: String) async throws {
        turnsBySessionID.removeValue(forKey: sessionID)
    }

    private func nextSequenceNumber(forSessionID sessionID: String) -> Int {
        turnsBySessionID[sessionID]?.compactMap(\.sequenceNumber).max().map { $0 + 1 } ?? 0
    }

    private func normalizedSequenceNumber(for turn: AgentTurn) -> Int {
        let next = nextSequenceNumber(forSessionID: turn.sessionID)
        guard let requested = turn.sequenceNumber else {
            return next
        }

        return max(requested, next)
    }

    private func compareTurns(_ lhs: AgentTurn, _ rhs: AgentTurn) -> Bool {
        switch (lhs.sequenceNumber, rhs.sequenceNumber) {
        case let (lhs?, rhs?):
            return lhs < rhs
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return false
        }
    }
}

private extension AgentTurn {
    func withSequenceNumber(_ sequenceNumber: Int) -> AgentTurn {
        AgentTurn(
            sessionID: sessionID,
            input: input,
            output: output,
            sequenceNumber: sequenceNumber
        )
    }
}
