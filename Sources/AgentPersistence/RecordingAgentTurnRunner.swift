import AgentCore
import Foundation

public struct RecordingAgentTurnRunner<Base: AgentTurnRunner>: AgentTurnRunner {
    public let base: Base
    public let session: AgentSession
    public let sessionStore: any AgentSessionStore
    public let turnStore: any AgentTurnStore

    public init(
        base: Base,
        session: AgentSession,
        sessionStore: any AgentSessionStore,
        turnStore: any AgentTurnStore
    ) {
        self.base = base
        self.session = session
        self.sessionStore = sessionStore
        self.turnStore = turnStore
    }

    public func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let baseStream = try base.runTurn(input: input)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await sessionStore.saveSession(session)

                    var completedMessages: [AgentMessage]?
                    for try await event in baseStream {
                        if case .messagesCompleted(let messages) = event {
                            completedMessages = messages
                        }
                        continuation.yield(event)
                    }

                    if let completedMessages {
                        let turn = AgentTurn(
                            sessionID: session.id,
                            input: input,
                            output: completedMessages
                        )
                        try await turnStore.appendTurn(turn)
                        if let persistedTurn = try await turnStore.turns(forSessionID: session.id).last {
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
}
