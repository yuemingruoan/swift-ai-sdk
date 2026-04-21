import AgentAnthropic
import AgentCore
import Testing

struct AnthropicTurnRunnerTests {
    @Test func turn_runner_returns_completed_messages_for_one_turn() async throws {
        let runner = AnthropicTurnRunner(
            client: AnthropicMessagesClient(
                transport: TurnRunnerTransport(
                    responses: [
                        AnthropicMessageResponse(
                            id: "msg_1",
                            model: "claude-sonnet-4-20250514",
                            role: .assistant,
                            content: [.text("Hello from Claude.")],
                            stopReason: .endTurn,
                            stopSequence: nil,
                            usage: .init(inputTokens: 10, outputTokens: 6)
                        ),
                    ]
                )
            ),
            configuration: .init(
                model: "claude-sonnet-4-20250514",
                maxTokens: 1024
            )
        )

        var events: [AgentStreamEvent] = []
        for try await event in try runner.runTurn(input: [.userText("hello")]) {
            events.append(event)
        }

        #expect(events == [
            .messagesCompleted([
                .init(role: .assistant, parts: [.text("Hello from Claude.")]),
            ]),
        ])
    }

    @Test func turn_runner_can_resolve_tool_calls_with_executor() async throws {
        let tool = ToolDescriptor.remote(
            name: "lookup_weather",
            transport: "weather-api",
            inputSchema: .object(
                properties: ["city": .string],
                required: ["city"]
            ),
            description: "Looks up the weather"
        )
        let registry = ToolRegistry()
        try await registry.register(tool)
        let executor = ToolExecutor(registry: registry)
        await executor.register(TurnRunnerWeatherTransport())

        let runner = AnthropicTurnRunner(
            client: AnthropicMessagesClient(
                transport: TurnRunnerTransport(
                    responses: [
                        AnthropicMessageResponse(
                            id: "msg_1",
                            model: "claude-sonnet-4-20250514",
                            role: .assistant,
                            content: [
                                .toolUse(
                                    .init(
                                        id: "toolu_123",
                                        name: "lookup_weather",
                                        input: ["city": .string("Paris")]
                                    )
                                ),
                            ],
                            stopReason: .toolUse,
                            stopSequence: nil,
                            usage: .init(inputTokens: 10, outputTokens: 5)
                        ),
                        AnthropicMessageResponse(
                            id: "msg_2",
                            model: "claude-sonnet-4-20250514",
                            role: .assistant,
                            content: [.text("Paris is sunny.")],
                            stopReason: .endTurn,
                            stopSequence: nil,
                            usage: .init(inputTokens: 18, outputTokens: 7)
                        ),
                    ]
                )
            ),
            configuration: .init(
                model: "claude-sonnet-4-20250514",
                maxTokens: 1024,
                tools: [tool]
            ),
            executor: executor
        )

        var events: [AgentStreamEvent] = []
        for try await event in try runner.runTurn(input: [.userText("weather in Paris?")]) {
            events.append(event)
        }

        #expect(events == [
            .toolCall(
                .init(
                    callID: "toolu_123",
                    invocation: .init(toolName: "lookup_weather", arguments: ["city": .string("Paris")])
                )
            ),
            .messagesCompleted([
                .init(role: .assistant, parts: [.text("Paris is sunny.")]),
            ]),
        ])
    }
}

private actor TurnRunnerTransport: AnthropicMessagesTransport {
    private let responses: [AnthropicMessageResponse]
    private var index = 0

    init(responses: [AnthropicMessageResponse]) {
        self.responses = responses
    }

    func createMessage(_ request: AnthropicMessagesRequest) async throws -> AnthropicMessageResponse {
        let response = responses[index]
        index += 1
        return response
    }
}

private actor TurnRunnerWeatherTransport: RemoteToolTransport {
    let transportID = "weather-api"

    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        #expect(invocation.arguments == ["city": .string("Paris")])
        return ToolResult(payload: .object(["forecast": .string("sunny")]))
    }
}
