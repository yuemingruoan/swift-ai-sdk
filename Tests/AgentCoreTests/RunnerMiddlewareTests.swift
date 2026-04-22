import Testing
@testable import AgentCore
@testable import AgentPersistence

struct RunnerMiddlewareTests {
    @Test func session_runner_redacts_completed_messages_and_state_without_touching_text_deltas() async throws {
        let middleware = AgentMiddlewareStack(
            messageRedaction: [RunnerRedactingMiddleware()]
        )
        let base = MiddlewareRecordingTurnRunner(
            emittedEvents: [
                .textDelta("Hel"),
                .messagesCompleted([AgentMessage(role: .assistant, parts: [.text("secret")])]),
            ]
        )
        let runner = AgentSessionRunner(base: base, middleware: middleware)
        let state = AgentConversationState(sessionID: "session-1")

        var events: [AgentSessionStreamEvent] = []
        for try await event in try runner.runTurn(
            state: state,
            input: [AgentMessage.userText("private")]
        ) {
            events.append(event)
        }

        #expect(events == [
            .event(.textDelta("Hel")),
            .event(.messagesCompleted([
                AgentMessage(role: .assistant, parts: [.text("[redacted]")]),
            ])),
            .stateUpdated(
                AgentConversationState(
                    sessionID: "session-1",
                    messages: [
                        .userText("[redacted]"),
                        AgentMessage(role: .assistant, parts: [.text("[redacted]")]),
                    ]
                )
            ),
        ])
    }

    @Test func recording_runner_redacts_completed_messages_and_persisted_turn() async throws {
        let middleware = AgentMiddlewareStack(
            messageRedaction: [RunnerRedactingMiddleware()]
        )
        let session = AgentSession(id: "session-1")
        let sessionStore = InMemoryAgentStore()
        let turnStore = InMemoryAgentStore()
        let base = MiddlewareRecordingTurnRunner(
            emittedEvents: [
                .textDelta("Hel"),
                .messagesCompleted([AgentMessage(role: .assistant, parts: [.text("secret")])]),
            ]
        )
        let runner = RecordingAgentTurnRunner(
            base: base,
            session: session,
            sessionStore: sessionStore,
            turnStore: turnStore,
            middleware: middleware
        )

        var events: [AgentStreamEvent] = []
        for try await event in try runner.runTurn(input: [AgentMessage.userText("private")]) {
            events.append(event)
        }

        #expect(events == [
            .textDelta("Hel"),
            .messagesCompleted([
                AgentMessage(role: .assistant, parts: [.text("[redacted]")]),
            ]),
            .turnCompleted(
                AgentTurn(
                    sessionID: "session-1",
                    input: [.userText("[redacted]")],
                    output: [AgentMessage(role: .assistant, parts: [.text("[redacted]")])],
                    sequenceNumber: 0
                )
            ),
        ])

        let persistedTurns = try await turnStore.turns(forSessionID: "session-1")
        #expect(persistedTurns == [
            AgentTurn(
                sessionID: "session-1",
                input: [.userText("[redacted]")],
                output: [AgentMessage(role: .assistant, parts: [.text("[redacted]")])],
                sequenceNumber: 0
            ),
        ])
    }
}

private struct RunnerRedactingMiddleware: AgentMessageRedactionMiddleware {
    func redact(
        _ messages: [AgentMessage],
        reason: AgentMessageRedactionReason
    ) async throws -> [AgentMessage] {
        messages.map { message in
            AgentMessage(
                role: message.role,
                parts: message.parts.map { part in
                    switch part {
                    case .text:
                        return .text("[redacted]")
                    case .image:
                        return part
                    }
                }
            )
        }
    }
}

private final class MiddlewareRecordingTurnRunner: AgentTurnRunner, @unchecked Sendable {
    let emittedEvents: [AgentStreamEvent]

    init(emittedEvents: [AgentStreamEvent]) {
        self.emittedEvents = emittedEvents
    }

    func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in emittedEvents {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
