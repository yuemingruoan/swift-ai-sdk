import AgentCore

/// In-memory reference implementation of both session and turn stores.
public actor InMemoryAgentStore: AgentSessionStore, AgentTurnStore {
    private var sessionsByID: [String: AgentSession]
    private var turnsBySessionID: [String: [AgentTurn]]

    /// Creates an empty in-memory store.
    public init() {
        self.sessionsByID = [:]
        self.turnsBySessionID = [:]
    }

    /// Saves or replaces a session by identifier.
    /// - Parameter session: Session value to store.
    /// - Throws: Never throws in the in-memory implementation, but matches the store protocol.
    public func saveSession(_ session: AgentSession) async throws {
        sessionsByID[session.id] = session
    }

    /// Loads a session by identifier.
    /// - Parameter id: Session identifier to look up.
    /// - Returns: The stored session, or `nil` if none exists.
    /// - Throws: Never throws in the in-memory implementation, but matches the store protocol.
    public func session(id: String) async throws -> AgentSession? {
        sessionsByID[id]
    }

    /// Returns a stable, deterministic order for the in-memory implementation.
    /// - Returns: All stored sessions sorted by identifier.
    /// - Throws: Never throws in the in-memory implementation, but matches the store protocol.
    public func listSessions() async throws -> [AgentSession] {
        sessionsByID.values.sorted { $0.id < $1.id }
    }

    /// Removes a session and any turns recorded under the same identifier.
    /// - Parameter id: Session identifier to remove.
    /// - Throws: Never throws in the in-memory implementation, but matches the store protocol.
    public func deleteSession(id: String) async throws {
        sessionsByID.removeValue(forKey: id)
        turnsBySessionID.removeValue(forKey: id)
    }

    /// Appends a turn and normalizes its sequence number for deterministic replay.
    /// - Parameter turn: Turn value to append.
    /// - Throws: Never throws in the in-memory implementation, but matches the store protocol.
    public func appendTurn(_ turn: AgentTurn) async throws {
        let storedTurn = turn.withSequenceNumber(
            normalizedSequenceNumber(for: turn)
        )
        turnsBySessionID[turn.sessionID, default: []].append(storedTurn)
    }

    /// Preserves append order by returning turns sorted by `sequenceNumber`.
    /// - Parameter sessionID: Session identifier whose turns should be returned.
    /// - Returns: Stored turns sorted into replay order.
    /// - Throws: Never throws in the in-memory implementation, but matches the store protocol.
    public func turns(forSessionID sessionID: String) async throws -> [AgentTurn] {
        turnsBySessionID[sessionID]?.sorted(by: compareTurns) ?? []
    }

    /// Deletes all turns recorded for a session identifier.
    /// - Parameter sessionID: Session identifier whose turns should be removed.
    /// - Throws: Never throws in the in-memory implementation, but matches the store protocol.
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
