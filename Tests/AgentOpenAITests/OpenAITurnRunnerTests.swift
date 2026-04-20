import AgentCore
import AgentOpenAI
import Foundation
import Testing

struct OpenAITurnRunnerTests {
    @Test func responses_turn_runner_streams_events_for_one_turn() async throws {
        let tool = ToolDescriptor.remote(
            name: "lookup_weather",
            transport: "weather-api",
            inputSchema: .object(properties: ["city": .string], required: ["city"])
        )
        let registry = ToolRegistry()
        try await registry.register(tool)
        let executor = ToolExecutor(registry: registry)
        await executor.register(OpenAITurnRunnerWeatherTransport())
        let streamingTransport = TurnRunnerStreamingTransport(
            eventSequences: [
                [
                    OpenAIResponseStreamEvent.outputTextDelta(
                        OpenAIResponseTextDeltaEvent(
                            itemID: "msg_1",
                            outputIndex: 0,
                            contentIndex: 0,
                            delta: "Checking",
                            sequenceNumber: 1
                        )
                    ),
                    OpenAIResponseStreamEvent.responseCompleted(
                        OpenAIResponse(
                            id: "resp_1",
                            status: .completed,
                            output: [
                                OpenAIResponseOutputItem.functionCall(
                                    OpenAIResponseFunctionCall(
                                        callID: "call_123",
                                        name: "lookup_weather",
                                        arguments: "{\"city\":\"Paris\"}",
                                        status: .completed
                                    )
                                ),
                            ]
                        )
                    ),
                ],
                [
                    OpenAIResponseStreamEvent.outputTextDelta(
                        OpenAIResponseTextDeltaEvent(
                            itemID: "msg_2",
                            outputIndex: 0,
                            contentIndex: 0,
                            delta: "Paris is sunny.",
                            sequenceNumber: 2
                        )
                    ),
                    OpenAIResponseStreamEvent.responseCompleted(
                        OpenAIResponse(
                            id: "resp_2",
                            status: .completed,
                            output: [
                                OpenAIResponseOutputItem.message(
                                    OpenAIResponseMessage(
                                        id: "msg_2",
                                        role: .assistant,
                                        content: [OpenAIResponseMessageContent.outputText("Paris is sunny.")]
                                    )
                                ),
                            ]
                        )
                    ),
                ],
            ]
        )
        let runner = OpenAIResponsesTurnRunner(
            client: OpenAIResponsesClient(
                transport: TurnRunnerResponsesTransport(),
                streamingTransport: streamingTransport
            ),
            configuration: OpenAIResponsesTurnRunnerConfiguration(
                model: "gpt-5.4",
                tools: [tool],
                toolChoice: .required,
                stream: true
            ),
            executor: executor
        )

        var events: [AgentStreamEvent] = []
        for try await event in try runner.runTurn(input: [AgentMessage.userText("weather in Paris?")]) {
            events.append(event)
        }

        #expect(events == [
            .textDelta("Checking"),
            .toolCall(
                .init(
                    callID: "call_123",
                    invocation: .init(toolName: "lookup_weather", arguments: ["city": .string("Paris")])
                )
            ),
            .textDelta("Paris is sunny."),
            .messagesCompleted([
                .init(role: .assistant, parts: [.text("Paris is sunny.")]),
            ]),
        ])
    }

    @Test func realtime_turn_runner_sends_messages_and_returns_completed_turn_events() async throws {
        let session = TurnRunnerWebSocketSession(
            incomingMessages: [
                #"{"type":"response.output_text.delta","delta":"Par"}"#,
                #"{"type":"response.done","response":{"id":"resp_2","status":"completed","output":[{"type":"message","id":"msg_2","role":"assistant","content":[{"type":"output_text","text":"Paris is sunny."}]}]}}"#,
            ]
        )
        let client = OpenAIRealtimeWebSocketClient(
            configuration: .init(apiKey: "sk-test", model: "gpt-realtime"),
            session: session
        )
        let runner = OpenAIRealtimeTurnRunner(
            client: client,
            configuration: OpenAIRealtimeTurnRunnerConfiguration(
                instructions: "Be concise",
                tools: [],
                toolChoice: nil
            )
        )

        var events: [AgentStreamEvent] = []
        for try await event in try runner.runTurn(
            input: [AgentMessage(role: .user, parts: [.text("weather in Paris?")])]
        ) {
            events.append(event)
        }

        #expect(events == [
            .textDelta("Par"),
            .messagesCompleted([
                .init(role: .assistant, parts: [.text("Paris is sunny.")]),
            ]),
        ])

        let sentTexts = await session.connection.sentTexts
        #expect(sentTexts.count == 3)
        #expect(sentTexts[0].contains("\"type\":\"session.update\""))
        #expect(sentTexts[1].contains("\"type\":\"conversation.item.create\""))
        #expect(sentTexts[1].contains("\"weather in Paris?\""))
        #expect(sentTexts[2].contains("\"type\":\"response.create\""))
    }
}

private actor OpenAITurnRunnerWeatherTransport: RemoteToolTransport {
    let transportID = "weather-api"

    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        #expect(invocation.arguments == ["city": .string("Paris")])
        return ToolResult(payload: .object(["forecast": .string("sunny")]))
    }
}

private actor TurnRunnerResponsesTransport: OpenAIResponsesTransport {
    func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse {
        OpenAIResponse(id: "unused", status: .completed, output: [])
    }
}

private final class TurnRunnerStreamingTransport: @unchecked Sendable, OpenAIResponsesStreamingTransport {
    private let eventSequences: [[OpenAIResponseStreamEvent]]
    private let lock = NSLock()
    private var index = 0

    init(eventSequences: [[OpenAIResponseStreamEvent]]) {
        self.eventSequences = eventSequences
    }

    func streamResponse(_ request: OpenAIResponseRequest) -> AsyncThrowingStream<OpenAIResponseStreamEvent, Error> {
        let events = lock.withLock { () -> [OpenAIResponseStreamEvent] in
            let currentIndex = index
            index += 1
            return eventSequences[currentIndex]
        }

        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private final class TurnRunnerWebSocketSession: @unchecked Sendable, OpenAIWebSocketSession {
    let connection: TurnRunnerWebSocketConnection

    init(incomingMessages: [String]) {
        self.connection = TurnRunnerWebSocketConnection(incomingMessages: incomingMessages)
    }

    func makeConnection(with request: URLRequest) -> any OpenAIWebSocketConnection {
        connection
    }
}

private actor TurnRunnerWebSocketConnection: OpenAIWebSocketConnection {
    private var incomingMessages: [String]
    private(set) var sentTexts: [String] = []

    init(incomingMessages: [String]) {
        self.incomingMessages = incomingMessages
    }

    func connect() async {}

    func send(text: String) async throws {
        sentTexts.append(text)
    }

    func receiveText() async throws -> String {
        incomingMessages.removeFirst()
    }

    func cancel() async {}
}
