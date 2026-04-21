import Foundation

public enum AgentSessionStreamEvent: Equatable, Sendable {
    case event(AgentStreamEvent)
    case stateUpdated(AgentConversationState)
}

public struct AgentSessionRunner<Base: AgentTurnRunner>: Sendable {
    public let base: Base

    public init(base: Base) {
        self.base = base
    }

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
                            completedMessages = messages
                        }
                        continuation.yield(.event(event))
                    }

                    if let completedMessages {
                        continuation.yield(
                            .stateUpdated(
                                state.appendingTurn(
                                    input: input,
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
}
