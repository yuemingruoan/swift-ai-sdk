import AgentCore
import Foundation

/// Wraps a turn runner and persists completed turns through store protocols.
public struct RecordingAgentTurnRunner<Base: AgentTurnRunner>: AgentTurnRunner {
    public let base: Base
    public let session: AgentSession
    public let sessionStore: any AgentSessionStore
    public let turnStore: any AgentTurnStore
    public let middleware: AgentMiddlewareStack

    /// Creates a recording wrapper around an existing turn runner.
    /// - Parameters:
    ///   - base: Turn runner that performs the actual provider work.
    ///   - session: Session identity used when persisting completed turns.
    ///   - sessionStore: Store that persists session metadata.
    ///   - turnStore: Store that persists completed turns.
    ///   - middleware: Shared middleware stack used for redaction and audit.
    public init(
        base: Base,
        session: AgentSession,
        sessionStore: any AgentSessionStore,
        turnStore: any AgentTurnStore,
        middleware: AgentMiddlewareStack = AgentMiddlewareStack()
    ) {
        self.base = base
        self.session = session
        self.sessionStore = sessionStore
        self.turnStore = turnStore
        self.middleware = middleware
    }

    /// Runs a turn, persists the completed session/turn data, and emits a final persisted turn event.
    /// - Parameter input: Input messages for the turn being executed.
    /// - Returns: A stream of provider-neutral events ending with `.turnCompleted` when persistence succeeds.
    /// - Throws: An error if the wrapped runner fails or if session/turn persistence cannot be completed.
    public func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let baseStream = try base.runTurn(input: input)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await sessionStore.saveSession(session)

                    var completedMessages: [AgentMessage]?
                    for try await event in baseStream {
                        if case .messagesCompleted(let messages) = event {
                            let redactedMessages = try await redactMessages(
                                messages,
                                reason: .messagesCompleted
                            )
                            completedMessages = redactedMessages
                            continuation.yield(.messagesCompleted(redactedMessages))
                            continue
                        }
                        continuation.yield(event)
                    }

                    if let completedMessages {
                        let redactedInput = try await redactMessages(
                            input,
                            reason: .persistedTurn
                        )
                        let turn = AgentTurn(
                            sessionID: session.id,
                            input: redactedInput,
                            output: completedMessages
                        )
                        try await turnStore.appendTurn(turn)
                        if let persistedTurn = try await turnStore.turns(forSessionID: session.id).last {
                            await middleware.recordAuditEvent(
                                .messagesRedacted(
                                    .init(
                                        reason: .turnCompleted,
                                        originalCount: turn.input.count + turn.output.count,
                                        redactedCount: persistedTurn.input.count + persistedTurn.output.count
                                    )
                                )
                            )
                            continuation.yield(.turnCompleted(persistedTurn))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func redactMessages(
        _ messages: [AgentMessage],
        reason: AgentMessageRedactionReason
    ) async throws -> [AgentMessage] {
        let redactedMessages = try await middleware.redactMessages(messages, reason: reason)
        await middleware.recordAuditEvent(
            .messagesRedacted(
                .init(
                    reason: reason,
                    originalCount: messages.count,
                    redactedCount: redactedMessages.count
                )
            )
        )
        return redactedMessages
    }
}
