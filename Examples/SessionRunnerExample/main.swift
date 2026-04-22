import ExampleSupport
import Foundation
import OpenAIAgentRuntime

@main
enum SessionRunnerExample {
    static func main() async throws {
        let prompts = Array(CommandLine.arguments.dropFirst())
        let turns = prompts.isEmpty
            ? ["Hello there.", "What did I just ask you?"]
            : prompts

        let runner = AgentSessionRunner(base: DemoConversationTurnRunner())
        var state = AgentConversationState(sessionID: "example-session")

        for (index, prompt) in turns.enumerated() {
            ExampleEventPrinter.printDivider("Session Turn \(index + 1)")
            for try await event in try runner.runTurn(
                state: state,
                input: [.userText(prompt)]
            ) {
                ExampleEventPrinter.printSessionEvent(event)
                if case .stateUpdated(let updatedState) = event {
                    state = updatedState
                }
            }
        }

        ExampleEventPrinter.printDivider("Final Conversation State")
        ExampleEventPrinter.printMessages(state.messages)
    }
}
