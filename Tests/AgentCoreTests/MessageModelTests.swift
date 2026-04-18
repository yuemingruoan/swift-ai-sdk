import Foundation
import Testing
@testable import AgentCore

struct MessageModelTests {
    @Test func message_round_trips_with_parts() throws {
        let message = AgentMessage(
            role: .user,
            parts: [.text("hello"), .image(url: URL(string: "https://example.com/a.png")!)]
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(AgentMessage.self, from: data)

        #expect(decoded == message)
    }

    @Test func turn_binds_input_and_output_messages() {
        let turn = AgentTurn(sessionID: "s1", input: [.userText("ping")], output: [])
        #expect(turn.sessionID == "s1")
        #expect(turn.input.count == 1)
    }

    @Test func session_round_trips_identifier_through_codable() throws {
        let session = AgentSession(id: "session-123")

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(AgentSession.self, from: data)

        #expect(decoded == session)
    }

    @Test func stream_event_round_trips_text_delta_through_codable() throws {
        let event = AgentStreamEvent.textDelta("partial response")

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentStreamEvent.self, from: data)

        #expect(decoded == event)
    }

    @Test func stream_event_round_trips_completed_turn_through_codable() throws {
        let turn = AgentTurn(
            sessionID: "session-123",
            input: [.userText("ping")],
            output: [.init(role: .assistant, parts: [.text("pong")])]
        )
        let event = AgentStreamEvent.turnCompleted(turn)

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentStreamEvent.self, from: data)

        #expect(decoded == event)
    }
}
