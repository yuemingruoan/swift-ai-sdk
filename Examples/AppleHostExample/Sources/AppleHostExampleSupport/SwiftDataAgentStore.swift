import AgentCore
import AgentPersistence
import Foundation
import SwiftData

@Model
final class PersistedAgentSession {
    @Attribute(.unique) var id: String
    var updatedAt: Date

    init(id: String, updatedAt: Date = .now) {
        self.id = id
        self.updatedAt = updatedAt
    }
}

@Model
final class PersistedAgentTurn {
    @Attribute(.unique) var id: String
    var sessionID: String
    var sequenceNumber: Int
    var inputData: Data
    var outputData: Data
    var createdAt: Date

    init(
        id: String,
        sessionID: String,
        sequenceNumber: Int,
        inputData: Data,
        outputData: Data,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sequenceNumber = sequenceNumber
        self.inputData = inputData
        self.outputData = outputData
        self.createdAt = createdAt
    }
}

@MainActor
public final class SwiftDataAgentStore: AgentSessionStore, AgentTurnStore {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    public static func inMemory() throws -> SwiftDataAgentStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PersistedAgentSession.self,
            PersistedAgentTurn.self,
            configurations: configuration
        )
        return SwiftDataAgentStore(container: container)
    }

    public static func persistent() throws -> SwiftDataAgentStore {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent(
            "dev.swift-ai-sdk.apple-host-example",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("AppleHostExample.store")
        let configuration = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(
            for: PersistedAgentSession.self,
            PersistedAgentTurn.self,
            configurations: configuration
        )
        return SwiftDataAgentStore(container: container)
    }

    public func saveSession(_ session: AgentSession) async throws {
        if let existing = try fetchSessionEntity(id: session.id) {
            existing.updatedAt = .now
        } else {
            context.insert(PersistedAgentSession(id: session.id))
        }
        try context.save()
    }

    public func session(id: String) async throws -> AgentSession? {
        try fetchSessionEntity(id: id).map { AgentSession(id: $0.id) }
    }

    public func listSessions() async throws -> [AgentSession] {
        let descriptor = FetchDescriptor<PersistedAgentSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { AgentSession(id: $0.id) }
    }

    public func deleteSession(id: String) async throws {
        if let session = try fetchSessionEntity(id: id) {
            context.delete(session)
        }
        try deleteTurnEntities(forSessionID: id)
        try context.save()
    }

    public func appendTurn(_ turn: AgentTurn) async throws {
        let sequenceNumber = try nextSequenceNumber(forSessionID: turn.sessionID)
        let entity = PersistedAgentTurn(
            id: "\(turn.sessionID)#\(sequenceNumber)",
            sessionID: turn.sessionID,
            sequenceNumber: sequenceNumber,
            inputData: try encoder.encode(turn.input),
            outputData: try encoder.encode(turn.output)
        )
        context.insert(entity)

        if let session = try fetchSessionEntity(id: turn.sessionID) {
            session.updatedAt = .now
        } else {
            context.insert(PersistedAgentSession(id: turn.sessionID))
        }

        try context.save()
    }

    public func turns(forSessionID sessionID: String) async throws -> [AgentTurn] {
        let descriptor = FetchDescriptor<PersistedAgentTurn>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.sequenceNumber)]
        )
        return try context.fetch(descriptor).map { entity in
            AgentTurn(
                sessionID: entity.sessionID,
                input: try decoder.decode([AgentMessage].self, from: entity.inputData),
                output: try decoder.decode([AgentMessage].self, from: entity.outputData),
                sequenceNumber: entity.sequenceNumber
            )
        }
    }

    public func deleteTurns(forSessionID sessionID: String) async throws {
        try deleteTurnEntities(forSessionID: sessionID)
        try context.save()
    }

    public func conversationState(sessionID: String) async throws -> AgentConversationState? {
        let turns = try await turns(forSessionID: sessionID)
        guard !turns.isEmpty else {
            return nil
        }

        return turns.reduce(into: AgentConversationState(sessionID: sessionID)) { state, turn in
            state = state.appendingTurn(input: turn.input, output: turn.output)
        }
    }

    private func fetchSessionEntity(id: String) throws -> PersistedAgentSession? {
        var descriptor = FetchDescriptor<PersistedAgentSession>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func nextSequenceNumber(forSessionID sessionID: String) throws -> Int {
        let descriptor = FetchDescriptor<PersistedAgentTurn>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.sequenceNumber, order: .reverse)]
        )
        let latest = try context.fetch(descriptor).first?.sequenceNumber ?? 0
        return latest + 1
    }

    private func deleteTurnEntities(forSessionID sessionID: String) throws {
        let descriptor = FetchDescriptor<PersistedAgentTurn>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        for turn in try context.fetch(descriptor) {
            context.delete(turn)
        }
    }
}
