import Foundation
import AgentCore
import AgentPersistence
import Testing

struct AgentPersistenceMapperTests {
    @Test func maps_session_to_record_and_back() {
        let session = AgentSession(id: "session-1")

        let record = AgentPersistenceMapper.sessionRecord(from: session)
        let restored = AgentPersistenceMapper.session(from: record)

        #expect(record == AgentSessionRecord(id: "session-1"))
        #expect(restored == session)
    }

    @Test func maps_turn_to_record_and_back_preserving_sequence_number() {
        let turn = AgentTurn(
            sessionID: "session-1",
            input: [.userText("ping")],
            output: [assistantMessage("pong")],
            sequenceNumber: 7
        )

        let record = AgentPersistenceMapper.turnRecord(from: turn)
        let restored = AgentPersistenceMapper.turn(from: record)

        #expect(record.sequenceNumber == 7)
        #expect(restored == turn)
    }

    @Test func maps_turn_records_preserving_message_parts() {
        let turn = AgentTurn(
            sessionID: "session-1",
            input: [
                AgentMessage(
                    role: .user,
                    parts: [
                        .text("describe this"),
                        .image(url: URL(string: "https://example.com/cat.png")!),
                    ]
                ),
            ],
            output: [
                AgentMessage(
                    role: .assistant,
                    parts: [
                        .text("A cat"),
                    ]
                ),
            ],
            sequenceNumber: 3
        )

        let record = AgentPersistenceMapper.turnRecord(from: turn)

        #expect(record.input == turn.input)
        #expect(record.output == turn.output)
        #expect(AgentPersistenceMapper.turn(from: record) == turn)
    }

    @Test func maps_record_without_sequence_number_back_to_runtime_model() {
        let record = AgentTurnRecord(
            sessionID: "session-1",
            input: [.userText("ping")],
            output: [assistantMessage("pong")],
            sequenceNumber: nil
        )

        #expect(AgentPersistenceMapper.turn(from: record) == AgentTurn(
            sessionID: "session-1",
            input: [.userText("ping")],
            output: [assistantMessage("pong")],
            sequenceNumber: nil
        ))
    }
}

private func assistantMessage(_ text: String) -> AgentMessage {
    AgentMessage(role: .assistant, parts: [.text(text)])
}
