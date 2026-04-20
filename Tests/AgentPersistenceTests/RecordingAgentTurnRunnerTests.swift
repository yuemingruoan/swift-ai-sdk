import AgentCore
import AgentPersistence
import Testing

struct RecordingAgentTurnRunnerTests {
    @Test func recording_runner_persists_completed_turn_and_emits_turn_completed() async throws {
        let store = InMemoryAgentStore()
        let runner = RecordingAgentTurnRunner(
            base: StubTurnRunner(
                emittedEvents: [
                    .textDelta("Hel"),
                    .messagesCompleted([assistantMessage("hello")]),
                ]
            ),
            session: AgentSession(id: "session-1"),
            sessionStore: store,
            turnStore: store
        )

        var events: [AgentStreamEvent] = []
        for try await event in try runner.runTurn(input: [AgentMessage.userText("ping")]) {
            events.append(event)
        }

        #expect(events == [
            .textDelta("Hel"),
            .messagesCompleted([assistantMessage("hello")]),
            .turnCompleted(
                AgentTurn(
                    sessionID: "session-1",
                    input: [.userText("ping")],
                    output: [assistantMessage("hello")],
                    sequenceNumber: 0
                )
            ),
        ])
        #expect(try await store.session(id: "session-1") == .init(id: "session-1"))
        #expect(try await store.turns(forSessionID: "session-1") == [
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("ping")],
                output: [assistantMessage("hello")],
                sequenceNumber: 0
            ),
        ])
    }

    @Test func recording_runner_skips_persistence_when_turn_never_completes() async throws {
        let store = InMemoryAgentStore()
        let runner = RecordingAgentTurnRunner(
            base: StubTurnRunner(emittedEvents: [.textDelta("partial")]),
            session: AgentSession(id: "session-1"),
            sessionStore: store,
            turnStore: store
        )

        var events: [AgentStreamEvent] = []
        for try await event in try runner.runTurn(input: [AgentMessage.userText("ping")]) {
            events.append(event)
        }

        #expect(events == [.textDelta("partial")])
        #expect(try await store.session(id: "session-1") == .init(id: "session-1"))
        #expect(try await store.turns(forSessionID: "session-1").isEmpty)
    }
}

private struct StubTurnRunner: AgentTurnRunner {
    let emittedEvents: [AgentStreamEvent]

    func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in emittedEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private func assistantMessage(_ text: String) -> AgentMessage {
    AgentMessage(role: .assistant, parts: [.text(text)])
}
