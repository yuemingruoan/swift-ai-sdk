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
}
