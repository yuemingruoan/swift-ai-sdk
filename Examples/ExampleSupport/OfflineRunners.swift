import AgentCore
import Foundation

public struct DemoConversationTurnRunner: AgentTurnRunner, Sendable {
    public init() {}

    public func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let turnIndex = input.filter { $0.role == .user }.count
        let lastPrompt = input.last(where: { $0.role == .user }).map(render(message:)) ?? "(no user input)"
        let reply = "Assistant turn \(turnIndex): replying to '\(lastPrompt)' with \(input.count) total messages in context."

        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(reply))
            continuation.yield(
                .messagesCompleted([
                    AgentMessage(role: .assistant, parts: [.text(reply)]),
                ])
            )
            continuation.finish()
        }
    }
}

public func render(message: AgentMessage) -> String {
    message.parts.map(render).joined(separator: " ")
}

private func render(_ part: MessagePart) -> String {
    switch part {
    case .text(let text):
        return text
    case .image(let url):
        return "[image: \(url.absoluteString)]"
    }
}
