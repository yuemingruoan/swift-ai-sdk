import AgentCore

public protocol AgentSessionStore: Sendable {
    func saveSession(_ session: AgentSession) async throws
    func session(id: String) async throws -> AgentSession?
    /// Collection ordering is implementation-defined.
    func listSessions() async throws -> [AgentSession]
    func deleteSession(id: String) async throws
}
