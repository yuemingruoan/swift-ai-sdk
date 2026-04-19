import AgentCore

public protocol AgentSessionStore: Sendable {
    func saveSession(_ session: AgentSession) async throws
    func session(id: String) async -> AgentSession?
    func listSessions() async -> [AgentSession]
    func deleteSession(id: String) async throws
}
