import AgentAnthropic
import AgentCore
import ExampleSupport
import Foundation

@main
enum AnthropicToolLoopExample {
    static func main() async throws {
        let apiKey = ExampleEnvironment.require(
            "ANTHROPIC_API_KEY",
            help: "Set ANTHROPIC_API_KEY before running AnthropicToolLoopExample."
        )
        let model = ExampleEnvironment.value(
            "ANTHROPIC_MODEL",
            default: "claude-sonnet-4-20250514"
        )
        let baseURL = ExampleEnvironment.url(
            "ANTHROPIC_BASE_URL",
            default: "https://api.anthropic.com/v1"
        )
        let version = ExampleEnvironment.value(
            "ANTHROPIC_VERSION",
            default: "2023-06-01"
        )
        let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
        let input = prompt.isEmpty
            ? "What is the weather in Paris? Use the tool."
            : prompt

        let tool = demoWeatherToolDescriptor()
        let registry = ToolRegistry()
        try await registry.register(tool)
        let executor = ToolExecutor(registry: registry)
        await executor.register(DemoWeatherTransport())

        let transport = URLSessionAnthropicMessagesTransport(
            configuration: .init(
                apiKey: apiKey,
                baseURL: baseURL,
                version: version
            )
        )
        let client = AnthropicMessagesClient(transport: transport)
        let runner = AnthropicTurnRunner(
            client: client,
            configuration: .init(
                model: model,
                maxTokens: 1024,
                tools: [tool]
            ),
            executor: executor
        )

        ExampleEventPrinter.printDivider("Anthropic Tool Loop")
        for try await event in try runner.runTurn(input: [.userText(input)]) {
            ExampleEventPrinter.printEvent(event)
        }
    }
}
