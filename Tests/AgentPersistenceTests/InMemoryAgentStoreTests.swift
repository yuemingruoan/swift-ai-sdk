import AgentCore
import AgentPersistence
import Testing

struct InMemoryAgentStoreTests {
    @Test func savesAndLoadsSessions() async throws {
        let store = InMemoryAgentStore()
        let session = AgentSession(id: "session-b")

        try await store.saveSession(session)

        #expect(await store.session(id: session.id) == session)
    }

    @Test func listsSessionsDeterministicallyByIdentifier() async throws {
        let store = InMemoryAgentStore()

        try await store.saveSession(.init(id: "session-c"))
        try await store.saveSession(.init(id: "session-a"))
        try await store.saveSession(.init(id: "session-b"))

        let sessions = await store.listSessions()
        #expect(sessions.map(\.id) == ["session-a", "session-b", "session-c"])
    }

    @Test func appendsTurnsAndReadsThemBackInAppendOrder() async throws {
        let store = InMemoryAgentStore()
        try await store.saveSession(.init(id: "session-1"))

        let firstTurn = AgentTurn(
            sessionID: "session-1",
            input: [.userText("first")],
            output: [assistantMessage("one")]
        )
        let secondTurn = AgentTurn(
            sessionID: "session-1",
            input: [.userText("second")],
            output: [assistantMessage("two")]
        )

        try await store.appendTurn(firstTurn)
        try await store.appendTurn(secondTurn)

        let turns = await store.turns(forSessionID: "session-1")
        #expect(turns == [firstTurn, secondTurn])
    }

    @Test func deletingSessionAlsoClearsTurns() async throws {
        let store = InMemoryAgentStore()
        let session = AgentSession(id: "session-1")
        try await store.saveSession(session)
        try await store.appendTurn(
            AgentTurn(
                sessionID: session.id,
                input: [.userText("hello")],
                output: [assistantMessage("world")]
            )
        )

        try await store.deleteSession(id: session.id)

        #expect(await store.session(id: session.id) == nil)
        #expect(await store.turns(forSessionID: session.id).isEmpty)
    }

    @Test func appendingTurnForMissingSessionThrowsMissingSessionError() async {
        let store = InMemoryAgentStore()
        let turn = AgentTurn(
            sessionID: "missing-session",
            input: [.userText("ping")],
            output: [assistantMessage("pong")]
        )

        await #expect(throws: AgentPersistenceError.missingSession(id: "missing-session")) {
            try await store.appendTurn(turn)
        }
    }
}

private func assistantMessage(_ text: String) -> AgentMessage {
    AgentMessage(role: .assistant, parts: [.text(text)])
}
