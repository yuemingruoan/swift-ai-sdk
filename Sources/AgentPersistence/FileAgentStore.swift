import AgentCore
import Foundation

public actor FileAgentStore: AgentSessionStore, AgentTurnStore {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let sessionsFileURL: URL
    private let turnsFileURL: URL

    private var sessionsByID: [String: AgentSession]
    private var turnsBySessionID: [String: [AgentTurn]]

    public init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.sessionsFileURL = directoryURL.appendingPathComponent("sessions.json")
        self.turnsFileURL = directoryURL.appendingPathComponent("turns.json")

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        self.sessionsByID = try FileAgentStore.loadSessions(
            from: sessionsFileURL,
            decoder: decoder
        )
        self.turnsBySessionID = try FileAgentStore.loadTurns(
            from: turnsFileURL,
            decoder: decoder
        )
    }

    public func saveSession(_ session: AgentSession) async throws {
        sessionsByID[session.id] = session
        try persistSessions()
    }

    public func session(id: String) async throws -> AgentSession? {
        sessionsByID[id]
    }

    public func listSessions() async throws -> [AgentSession] {
        sessionsByID.values.sorted { $0.id < $1.id }
    }

    public func deleteSession(id: String) async throws {
        sessionsByID.removeValue(forKey: id)
        turnsBySessionID.removeValue(forKey: id)
        try persistSessions()
        try persistTurns()
    }

    public func appendTurn(_ turn: AgentTurn) async throws {
        let storedTurn = turn.withSequenceNumber(
            normalizedSequenceNumber(for: turn)
        )
        turnsBySessionID[turn.sessionID, default: []].append(storedTurn)
        try persistTurns()
    }

    public func turns(forSessionID sessionID: String) async throws -> [AgentTurn] {
        turnsBySessionID[sessionID]?.sorted(by: compareTurns) ?? []
    }

    public func deleteTurns(forSessionID sessionID: String) async throws {
        turnsBySessionID.removeValue(forKey: sessionID)
        try persistTurns()
    }

    private func persistSessions() throws {
        let records = sessionsByID.values
            .sorted { $0.id < $1.id }
            .map(AgentPersistenceMapper.sessionRecord(from:))
        let data = try encoder.encode(records)
        try data.write(to: sessionsFileURL, options: .atomic)
    }

    private func persistTurns() throws {
        let records = turnsBySessionID
            .keys
            .sorted()
            .flatMap { sessionID in
                (turnsBySessionID[sessionID] ?? [])
                    .sorted(by: compareTurns)
                    .map(AgentPersistenceMapper.turnRecord(from:))
            }
        let data = try encoder.encode(records)
        try data.write(to: turnsFileURL, options: .atomic)
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

    private static func loadSessions(
        from fileURL: URL,
        decoder: JSONDecoder
    ) throws -> [String: AgentSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        let records = try decoder.decode([AgentSessionRecord].self, from: data)
        return Dictionary(
            uniqueKeysWithValues: records.map { record in
                let session = AgentPersistenceMapper.session(from: record)
                return (session.id, session)
            }
        )
    }

    private static func loadTurns(
        from fileURL: URL,
        decoder: JSONDecoder
    ) throws -> [String: [AgentTurn]] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        let records = try decoder.decode([AgentTurnRecord].self, from: data)
        return Dictionary(grouping: records.map(AgentPersistenceMapper.turn(from:))) { turn in
            turn.sessionID
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
