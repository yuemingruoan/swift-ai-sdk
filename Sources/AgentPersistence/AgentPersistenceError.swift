public enum AgentPersistenceError: Error, Equatable, Sendable {
    case missingSession(id: String)
}
