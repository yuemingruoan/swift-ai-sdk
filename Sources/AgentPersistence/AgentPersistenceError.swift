import Foundation

/// Errors surfaced by persistence stores when on-disk state is unreadable or cannot be written.
public enum AgentPersistenceError: Error, Equatable, Sendable {
    case invalidPersistedData(fileName: String)
    case writeFailed(fileName: String)
}
