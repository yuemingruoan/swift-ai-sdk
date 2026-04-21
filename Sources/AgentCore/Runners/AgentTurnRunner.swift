import Foundation

/// Runs one model turn and emits provider-neutral stream events.
public protocol AgentTurnRunner: Sendable {
    /// Starts a single turn with fully prepared input messages.
    /// - Parameter input: Provider-neutral input messages for the turn.
    /// - Returns: A stream of provider-neutral events emitted while the turn is running.
    /// - Throws: An error if the runner cannot construct or start the provider request.
    func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error>
}
