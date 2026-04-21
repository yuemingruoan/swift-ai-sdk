import AgentCore
import AgentPersistence
import ExampleSupport
import Foundation

@main
enum PersistenceExample {
    static func main() async throws {
        let directory = CommandLine.arguments.dropFirst().first
            ?? "/tmp/swift-ai-sdk-persistence-example"
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)

        let store = try FileAgentStore(directoryURL: directoryURL)
        let runner = RecordingAgentTurnRunner(
            base: DemoConversationTurnRunner(),
            session: .init(id: "persistent-session"),
            sessionStore: store,
            turnStore: store
        )

        ExampleEventPrinter.printDivider("Persistence Run")
        for try await event in try runner.runTurn(input: [.userText("Persist this turn.")]) {
            ExampleEventPrinter.printEvent(event)
        }

        let sessions = try await store.listSessions()
        let turns = try await store.turns(forSessionID: "persistent-session")

        ExampleEventPrinter.printDivider("Persisted Sessions")
        for session in sessions {
            print("- \(session.id)")
        }

        ExampleEventPrinter.printDivider("Persisted Turns")
        for turn in turns {
            let prompt = turn.input.last.map(render(message:)) ?? "(no input)"
            let reply = turn.output.last.map(render(message:)) ?? "(no output)"
            print("- sequence=\(turn.sequenceNumber ?? -1) input=\(prompt) output=\(reply)")
        }

        print("\nStore directory: \(directoryURL.path)")
    }
}
