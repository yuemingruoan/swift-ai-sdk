import Foundation
import Testing
@testable import AgentCore

struct AgentConversationStateTests {
    @Test func conversation_state_starts_empty_for_a_session() {
        let state = AgentConversationState(sessionID: "session-1")

        #expect(state.sessionID == "session-1")
        #expect(state.messages.isEmpty)
        #expect(state.continuation.isEmpty)
    }

    @Test func conversation_state_appends_turn_io_and_preserves_continuation() {
        let initial = AgentConversationState(
            sessionID: "session-1",
            messages: [
                .userText("Earlier question"),
                assistantMessage("Earlier answer"),
            ],
            continuation: ["response_id": "resp_123"]
        )

        let updated = initial.appendingTurn(
            input: [.userText("Next question")],
            output: [assistantMessage("Next answer")]
        )

        #expect(updated.sessionID == "session-1")
        #expect(updated.messages == [
            .userText("Earlier question"),
            assistantMessage("Earlier answer"),
            .userText("Next question"),
            assistantMessage("Next answer"),
        ])
        #expect(updated.continuation == ["response_id": "resp_123"])
    }

    @Test func conversation_state_round_trips_through_codable() throws {
        let state = AgentConversationState(
            sessionID: "session-1",
            messages: [
                .userText("describe this"),
                AgentMessage(role: .assistant, parts: [.text("done")]),
            ],
            continuation: [
                "response_id": "resp_123",
                "conversation_id": "conv_456",
            ]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AgentConversationState.self, from: data)

        #expect(decoded == state)
    }

    @Test func run_context_defaults_conversation_to_session_identifier() {
        let context = AgentRunContext(session: AgentSession(id: "session-1"))

        #expect(context.session == AgentSession(id: "session-1"))
        #expect(context.conversation == AgentConversationState(sessionID: "session-1"))
    }
}

private func assistantMessage(_ text: String) -> AgentMessage {
    AgentMessage(role: .assistant, parts: [.text(text)])
}
