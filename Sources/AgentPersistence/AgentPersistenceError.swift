import Foundation

public enum AgentPersistenceError: Error, Equatable, Sendable {
    case invalidPersistedData(fileName: String)
    case writeFailed(fileName: String)
}
