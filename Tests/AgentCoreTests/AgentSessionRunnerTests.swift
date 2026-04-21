import Testing
@testable import AgentCore

struct AgentSessionRunnerTests {
    @Test func session_runner_prepends_history_and_emits_updated_state() async throws {
        let base = RecordingTurnRunner(
            emittedEvents: [
                .textDelta("Hel"),
                .messagesCompleted([assistantMessage("hello")]),
            ]
        )
        let runner = AgentSessionRunner(base: base)
        let state = AgentConversationState(
            sessionID: "session-1",
            messages: [
                .userText("Earlier question"),
                assistantMessage("Earlier answer"),
            ],
            continuation: ["response_id": "resp_123"]
        )

        var events: [AgentSessionStreamEvent] = []
        for try await event in try runner.runTurn(state: state, input: [.userText("ping")]) {
            events.append(event)
        }

        #expect(await base.recordedInputs == [[
            .userText("Earlier question"),
            assistantMessage("Earlier answer"),
            .userText("ping"),
        ]])
        #expect(events == [
            .event(.textDelta("Hel")),
            .event(.messagesCompleted([assistantMessage("hello")])),
            .stateUpdated(
                AgentConversationState(
                    sessionID: "session-1",
                    messages: [
                        .userText("Earlier question"),
                        assistantMessage("Earlier answer"),
                        .userText("ping"),
                        assistantMessage("hello"),
                    ],
                    continuation: ["response_id": "resp_123"]
                )
            ),
        ])
    }

    @Test func session_runner_omits_state_update_when_turn_never_completes() async throws {
        let base = RecordingTurnRunner(
            emittedEvents: [
                .textDelta("partial"),
            ]
        )
        let runner = AgentSessionRunner(base: base)
        let state = AgentConversationState(
            sessionID: "session-1",
            messages: [.userText("Earlier question")],
            continuation: ["response_id": "resp_123"]
        )

        var events: [AgentSessionStreamEvent] = []
        for try await event in try runner.runTurn(state: state, input: [.userText("ping")]) {
            events.append(event)
        }

        #expect(await base.recordedInputs == [[
            .userText("Earlier question"),
            .userText("ping"),
        ]])
        #expect(events == [
            .event(.textDelta("partial")),
        ])
    }
}

private final class RecordingTurnRunner: AgentTurnRunner, @unchecked Sendable {
    let emittedEvents: [AgentStreamEvent]
    private let recorder = InputRecorder()

    init(emittedEvents: [AgentStreamEvent]) {
        self.emittedEvents = emittedEvents
    }

    var recordedInputs: [[AgentMessage]] {
        get async {
            await recorder.recordedInputs
        }
    }

    func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        Task {
            await recorder.record(input)
        }

        return AsyncThrowingStream { continuation in
            for event in emittedEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private actor InputRecorder {
    private var inputs: [[AgentMessage]] = []

    var recordedInputs: [[AgentMessage]] {
        inputs
    }

    func record(_ input: [AgentMessage]) {
        inputs.append(input)
    }
}

private func assistantMessage(_ text: String) -> AgentMessage {
    AgentMessage(role: .assistant, parts: [.text(text)])
}
