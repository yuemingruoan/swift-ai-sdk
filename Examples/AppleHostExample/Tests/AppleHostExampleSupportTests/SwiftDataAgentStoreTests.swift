import AgentCore
import AgentPersistence
@testable import AppleHostExampleSupport
import Foundation
import SwiftData
import Testing

@MainActor
struct SwiftDataAgentStoreTests {
    @Test func session_and_turns_round_trip_through_swiftdata() async throws {
        let store = try SwiftDataAgentStore.inMemory()
        let session = AgentSession(id: "session-1")
        let turn = AgentTurn(
            sessionID: "session-1",
            input: [.userText("hello")],
            output: [assistantText("world")],
            sequenceNumber: nil
        )

        try await store.saveSession(session)
        try await store.appendTurn(turn)

        let sessions = try await store.listSessions()
        let turns = try await store.turns(forSessionID: "session-1")

        #expect(sessions == [session])
        #expect(turns.count == 1)
        #expect(turns[0].sessionID == "session-1")
        #expect(turns[0].sequenceNumber == 1)
        #expect(turns[0].input == [.userText("hello")])
        #expect(turns[0].output == [assistantText("world")])
    }

    @Test func turns_are_returned_in_sequence_order() async throws {
        let store = try SwiftDataAgentStore.inMemory()

        try await store.appendTurn(
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("first")],
                output: [assistantText("one")]
            )
        )
        try await store.appendTurn(
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("second")],
                output: [assistantText("two")]
            )
        )

        let turns = try await store.turns(forSessionID: "session-1")

        #expect(turns.map { $0.sequenceNumber } == [1, 2])
        #expect(turns.map { $0.input } == [[.userText("first")], [.userText("second")]])
    }

    @Test func conversation_state_rebuilds_from_persisted_turns() async throws {
        let store = try SwiftDataAgentStore.inMemory()
        try await store.appendTurn(
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("hello")],
                output: [assistantText("hi")]
            )
        )
        try await store.appendTurn(
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("weather?")],
                output: [assistantText("sunny")]
            )
        )

        let state = try await store.conversationState(sessionID: "session-1")

        let rebuilt = try #require(state)
        #expect(rebuilt.sessionID == "session-1")
        #expect(rebuilt.messages == [
            .userText("hello"),
            assistantText("hi"),
            .userText("weather?"),
            assistantText("sunny"),
        ])
    }

    @Test func deleting_session_removes_session_and_turns() async throws {
        let store = try SwiftDataAgentStore.inMemory()
        try await store.saveSession(AgentSession(id: "session-1"))
        try await store.appendTurn(
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("hello")],
                output: [assistantText("hi")]
            )
        )

        try await store.deleteSession(id: "session-1")

        #expect(try await store.session(id: "session-1") == nil)
        #expect(try await store.turns(forSessionID: "session-1").isEmpty)
    }
}

private func assistantText(_ text: String) -> AgentMessage {
    AgentMessage(role: .assistant, parts: [.text(text)])
}
