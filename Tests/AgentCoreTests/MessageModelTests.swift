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
        #expect(turn.sequenceNumber == nil)
    }

    @Test func turn_round_trips_sequence_number_through_codable() throws {
        let turn = AgentTurn(
            sessionID: "session-123",
            input: [.userText("ping")],
            output: [.init(role: .assistant, parts: [.text("pong")])],
            sequenceNumber: 7
        )

        let data = try JSONEncoder().encode(turn)
        let decoded = try JSONDecoder().decode(AgentTurn.self, from: data)

        #expect(decoded == turn)
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

    @Test func stream_event_round_trips_tool_call_through_codable() throws {
        let event = AgentStreamEvent.toolCall(
            .init(
                callID: "call_123",
                invocation: ToolInvocation(
                    toolName: "lookup_weather",
                    arguments: ["city": .string("Paris")]
                )
            )
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentStreamEvent.self, from: data)

        #expect(decoded == event)
    }

    @Test func stream_event_round_trips_completed_messages_through_codable() throws {
        let event = AgentStreamEvent.messagesCompleted([
            AgentMessage(role: .assistant, parts: [.text("done")]),
        ])

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentStreamEvent.self, from: data)

        #expect(decoded == event)
    }

    @Test func tool_value_round_trips_plain_json_shapes() throws {
        let value: ToolValue = .object([
            "city": .string("Paris"),
            "temperature": .integer(22),
            "confidence": .number(0.9),
            "alerts": .array([.string("sunny"), .boolean(false)]),
            "extra": .null,
        ])

        let data = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["city"] as? String == "Paris")
        #expect(object["temperature"] as? Int == 22)
        #expect(object["confidence"] as? Double == 0.9)
        let alerts = try #require(object["alerts"] as? [Any])
        #expect(alerts.count == 2)
        #expect(object.keys.contains("extra"))

        let decoded = try JSONDecoder().decode(ToolValue.self, from: data)
        #expect(decoded == value)
    }
}
