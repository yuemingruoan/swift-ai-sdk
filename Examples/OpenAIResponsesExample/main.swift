import AgentCore
import AgentOpenAI
import Foundation

@main
enum OpenAIResponsesExample {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let apiKey = environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            fputs("Set OPENAI_API_KEY before running this example.\n", stderr)
            Foundation.exit(1)
        }

        let model = environment["OPENAI_MODEL"] ?? "gpt-5.4"
        let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
        let input = prompt.isEmpty ? "Write one sentence about Swift concurrency." : prompt

        let transport = URLSessionOpenAIResponsesTransport(
            configuration: .init(apiKey: apiKey)
        )
        let streamingTransport = URLSessionOpenAIResponsesStreamingTransport(
            configuration: .init(apiKey: apiKey)
        )
        let client = OpenAIResponsesClient(
            transport: transport,
            streamingTransport: streamingTransport
        )
        let runner = OpenAIResponsesTurnRunner(
            client: client,
            configuration: .init(
                model: model,
                stream: true
            )
        )

        for try await event in try runner.runTurn(input: [.userText(input)]) {
            switch event {
            case .textDelta(let delta):
                print(delta, terminator: "")
                fflush(stdout)
            case .messagesCompleted(let messages):
                if !messages.isEmpty {
                    if !printedTrailingNewline(for: messages) {
                        print()
                    }
                }
            case .toolCall(let toolCall):
                print("\n[tool call] \(toolCall.invocation.toolName)")
            case .turnCompleted:
                break
            }
        }
    }
}

private func printedTrailingNewline(for messages: [AgentMessage]) -> Bool {
    guard
        let lastMessage = messages.last,
        let lastPart = lastMessage.parts.last,
        case .text(let text) = lastPart
    else {
        return false
    }

    return text.hasSuffix("\n")
}
