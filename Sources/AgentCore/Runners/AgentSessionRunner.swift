import Foundation

/// Session-level events emitted by ``AgentSessionRunner``.
public enum AgentSessionStreamEvent: Equatable, Sendable {
    case event(AgentStreamEvent)
    case stateUpdated(AgentConversationState)
}

/// Wraps a turn runner and updates ``AgentConversationState`` when a turn completes.
public struct AgentSessionRunner<Base: AgentTurnRunner>: Sendable {
    public let base: Base
    public let middleware: AgentMiddlewareStack

    /// Creates a session runner on top of a concrete turn runner.
    /// - Parameters:
    ///   - base: Underlying one-turn runner used for provider execution.
    ///   - middleware: Shared middleware stack used for redaction and audit.
    public init(
        base: Base,
        middleware: AgentMiddlewareStack = AgentMiddlewareStack()
    ) {
        self.base = base
        self.middleware = middleware
    }

    /// Runs one turn using the current conversation history and emits an updated state at completion.
    /// - Parameters:
    ///   - state: Existing conversation state to replay before the new turn input.
    ///   - input: New input messages for the next turn.
    /// - Returns: A stream containing forwarded turn events plus a final `.stateUpdated` event when the turn completes.
    /// - Throws: An error if the wrapped runner cannot start the turn.
    public func runTurn(
        state: AgentConversationState,
        input: [AgentMessage]
    ) throws -> AsyncThrowingStream<AgentSessionStreamEvent, Error> {
        let fullInput = state.messages + input
        let baseStream = try base.runTurn(input: fullInput)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var completedMessages: [AgentMessage]?

                    for try await event in baseStream {
                        if case .messagesCompleted(let messages) = event {
                            let redactedMessages = try await redactMessages(
                                messages,
                                reason: .messagesCompleted
                            )
                            completedMessages = redactedMessages
                            continuation.yield(.event(.messagesCompleted(redactedMessages)))
                            continue
                        }
                        continuation.yield(.event(event))
                    }

                    if let completedMessages {
                        let redactedInput = try await redactMessages(
                            input,
                            reason: .stateUpdated
                        )
                        continuation.yield(
                            .stateUpdated(
                                state.appendingTurn(
                                    input: redactedInput,
                                    output: completedMessages
                                )
                            )
                        )
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
