import AgentAnthropic
import AgentCore
import Foundation
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

    @Test func turn_runner_applies_request_and_response_middleware() async throws {
        let transport = MiddlewareAnthropicTransport()
        let middleware = AgentMiddlewareStack(
            modelRequest: [AnthropicTurnRunnerRequestMiddleware(prefix: "prepared:")],
            modelResponse: [AnthropicTurnRunnerResponseMiddleware(replacement: "[filtered]")]
        )
        let runner = AnthropicTurnRunner(
            client: AnthropicMessagesClient(transport: transport),
            configuration: .init(
                model: "claude-sonnet-4-20250514",
                maxTokens: 1024
            ),
            middleware: middleware
        )

        var events: [AgentStreamEvent] = []
        for try await event in try runner.runTurn(input: [.userText("hello")]) {
            events.append(event)
        }

        #expect(await transport.recordedTexts == ["prepared:hello"])
        #expect(events == [
            .messagesCompleted([
                .init(role: .assistant, parts: [.text("[filtered]")]),
            ]),
        ])
    }

    @Test func turn_runner_streams_text_deltas_when_enabled() async throws {
        let runner = AnthropicTurnRunner(
            client: AnthropicMessagesClient(
                transport: TurnRunnerTransport(responses: []),
                streamingTransport: TurnRunnerStreamingTransport(
                    eventSequences: [[
                        .messageStart(
                            .init(
                                message: .init(
                                    id: "msg_stream_1",
                                    model: "claude-sonnet-4-20250514",
                                    role: .assistant,
                                    content: [],
                                    stopReason: nil,
                                    stopSequence: nil,
                                    usage: .init(inputTokens: 10, outputTokens: 1)
                                )
                            )
                        ),
                        .contentBlockStart(.init(index: 0, contentBlock: .init(type: "text", text: ""))),
                        .contentBlockDelta(.init(index: 0, delta: .init(type: "text_delta", text: "Hello"))),
                        .contentBlockStop(.init(index: 0)),
                        .messageDelta(.init(delta: .init(stopReason: .endTurn, stopSequence: nil), usage: .init(outputTokens: 5))),
                        .messageStop,
                    ]]
                )
            ),
            configuration: .init(
                model: "claude-sonnet-4-20250514",
                maxTokens: 1024,
                stream: true
            )
        )

        var events: [AgentStreamEvent] = []
        for try await event in try runner.runTurn(input: [.userText("hello")]) {
            events.append(event)
        }

        #expect(events == [
            .textDelta("Hello"),
            .messagesCompleted([
                .init(role: .assistant, parts: [.text("Hello")]),
            ]),
        ])
    }

    @Test func turn_runner_can_include_thinking_blocks_when_enabled() async throws {
        let runner = AnthropicTurnRunner(
            client: AnthropicMessagesClient(
                transport: TurnRunnerTransport(responses: [
                    AnthropicMessageResponse(
                        id: "msg_1",
                        model: "claude-opus-4-6",
                        role: .assistant,
                        content: [
                            .thinking(.init(thinking: "internal")),
                            .text("Hello from Claude."),
                        ],
                        stopReason: .endTurn,
                        stopSequence: nil,
                        usage: .init(inputTokens: 10, outputTokens: 6)
                    ),
                ])
            ),
            configuration: .init(
                model: "claude-opus-4-6",
                maxTokens: 1024,
                projectionOptions: .preserveThinking
            )
        )

        var events: [AgentStreamEvent] = []
        for try await event in try runner.runTurn(input: [.userText("hello")]) {
            events.append(event)
        }

        #expect(events == [
            .messagesCompleted([
                .init(
                    role: .assistant,
                    parts: [.text("<thinking>internal</thinking>"), .text("Hello from Claude.")]
                ),
            ]),
        ])
    }

    @Test func turn_runner_omits_thinking_blocks_by_default() async throws {
        let runner = AnthropicTurnRunner(
            client: AnthropicMessagesClient(
                transport: TurnRunnerTransport(responses: [
                    AnthropicMessageResponse(
                        id: "msg_1",
                        model: "claude-opus-4-6",
                        role: .assistant,
                        content: [
                            .thinking(.init(thinking: "internal")),
                            .text("Hello from Claude."),
                        ],
                        stopReason: .endTurn,
                        stopSequence: nil,
                        usage: .init(inputTokens: 10, outputTokens: 6)
                    ),
                ])
            ),
            configuration: .init(
                model: "claude-opus-4-6",
                maxTokens: 1024
            )
        )

        var events: [AgentStreamEvent] = []
        for try await event in try runner.runTurn(input: [.userText("hello")]) {
            events.append(event)
        }

        #expect(events == [
            .messagesCompleted([
                .init(
                    role: .assistant,
                    parts: [.text("Hello from Claude.")]
                ),
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

private actor MiddlewareAnthropicTransport: AnthropicMessagesTransport {
    private(set) var recordedTexts: [String] = []

    func createMessage(_ request: AnthropicMessagesRequest) async throws -> AnthropicMessageResponse {
        recordedTexts = request.messages.compactMap { message in
            message.content.compactMap { block in
                guard case .text(let text) = block else {
                    return nil
                }
                return text
            }.joined()
        }

        return AnthropicMessageResponse(
            id: "msg_middleware",
            model: request.model,
            role: .assistant,
            content: [.text("provider text")],
            stopReason: .endTurn,
            stopSequence: nil,
            usage: .init(inputTokens: 10, outputTokens: 6)
        )
    }
}

private final class TurnRunnerStreamingTransport: @unchecked Sendable, AnthropicMessagesStreamingTransport {
    private let eventSequences: [[AnthropicMessageStreamEvent]]
    private let lock = NSLock()
    private var index = 0

    init(eventSequences: [[AnthropicMessageStreamEvent]]) {
        self.eventSequences = eventSequences
    }

    func streamMessage(_ request: AnthropicMessagesRequest) -> AsyncThrowingStream<AnthropicMessageStreamEvent, Error> {
        let events = lock.withLock { () -> [AnthropicMessageStreamEvent] in
            let events = eventSequences[index]
            index += 1
            return events
        }

        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private actor TurnRunnerWeatherTransport: RemoteToolTransport {
    let transportID = "weather-api"

    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        #expect(invocation.arguments == ["city": .string("Paris")])
        return ToolResult(payload: .object(["forecast": .string("sunny")]))
    }
}

private struct AnthropicTurnRunnerRequestMiddleware: AgentModelRequestMiddleware {
    let prefix: String

    func prepare(_ context: AgentModelRequestContext) async throws -> AgentModelRequestContext {
        AgentModelRequestContext(
            provider: context.provider,
            model: context.model,
            input: context.input.map { message in
                AgentMessage(
                    role: message.role,
                    parts: message.parts.map { part in
                        switch part {
                        case .text(let text):
                            .text(prefix + text)
                        case .image:
                            part
                        }
                    }
                )
            },
            tools: context.tools,
            stream: context.stream,
            metadata: context.metadata
        )
    }
}

private struct AnthropicTurnRunnerResponseMiddleware: AgentModelResponseMiddleware {
    let replacement: String

    func process(_ context: AgentModelResponseContext) async throws -> AgentModelResponseContext {
        AgentModelResponseContext(
            provider: context.provider,
            model: context.model,
            messages: context.messages.map { _ in
                AgentMessage(role: .assistant, parts: [.text(replacement)])
            },
            toolCalls: context.toolCalls,
            metadata: context.metadata
        )
    }
}
