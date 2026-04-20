import Foundation

public protocol AgentTurnRunner: Sendable {
    func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error>
}
