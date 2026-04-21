import AgentAnthropic
import AgentCore
import Foundation
import Testing

struct AnthropicMessagesClientTests {
    @Test func request_builder_applies_shared_transport_configuration() throws {
        let builder = AnthropicMessagesRequestBuilder(
            configuration: .init(
                apiKey: "sk-ant-test",
                transport: .init(
                    timeoutInterval: 8,
                    additionalHeaders: ["X-Test-Header": "fixture"],
                    userAgent: "swift-ai-sdk-tests/2.0",
                    requestID: "req_anthropic_123"
                )
            )
        )
        let request = try builder.makeURLRequest(
            for: AnthropicMessagesRequest(
                model: "claude-sonnet-4-20250514",
                maxTokens: 1024,
                messages: [.userText("hello")]
            )
        )

        #expect(request.timeoutInterval == 8)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-tests/2.0")
        #expect(request.value(forHTTPHeaderField: "X-Test-Header") == "fixture")
        #expect(request.value(forHTTPHeaderField: "X-Request-Id") == "req_anthropic_123")
    }

    @Test func transport_passes_shared_transport_configuration_to_injected_session() async throws {
        let session = RecordingAnthropicHTTPSession(
            data: """
            {
              "id":"msg_transport_config",
              "model":"claude-sonnet-4-20250514",
              "role":"assistant",
              "content":[{"type":"text","text":"hello"}],
              "stop_reason":"end_turn",
              "usage":{"input_tokens":10,"output_tokens":5}
            }
            """.data(using: .utf8)!,
            response: HTTPURLResponse(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        let transport = URLSessionAnthropicMessagesTransport(
            configuration: .init(
                apiKey: "sk-ant-test",
                transport: .init(
                    timeoutInterval: 8,
                    additionalHeaders: ["X-Test-Header": "fixture"],
                    userAgent: "swift-ai-sdk-tests/2.0",
                    requestID: "req_anthropic_transport_123"
                )
            ),
            session: session
        )

        let response = try await transport.createMessage(
            AnthropicMessagesRequest(
                model: "claude-sonnet-4-20250514",
                maxTokens: 1024,
                messages: [.userText("hello")]
            )
        )

        #expect(response.id == "msg_transport_config")
        let lastRequest = try #require(await session.lastRequest)
        #expect(lastRequest.timeoutInterval == 8)
        #expect(lastRequest.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-tests/2.0")
        #expect(lastRequest.value(forHTTPHeaderField: "X-Test-Header") == "fixture")
        #expect(lastRequest.value(forHTTPHeaderField: "X-Request-Id") == "req_anthropic_transport_123")
    }

    @Test func request_builder_sets_custom_user_agent_header() throws {
        let builder = AnthropicMessagesRequestBuilder(
            configuration: .init(
                apiKey: "sk-ant-test",
                userAgent: "swift-ai-sdk-tests/1.0"
            )
        )
        let request = try builder.makeURLRequest(
            for: AnthropicMessagesRequest(
                model: "claude-sonnet-4-20250514",
                maxTokens: 1024,
                messages: [.userText("hello")]
            )
        )

        #expect(request.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-tests/1.0")
    }

    @Test func request_builder_encodes_agent_messages_as_anthropic_messages() throws {
        let request = try AnthropicMessagesRequest(
            model: "claude-sonnet-4-20250514",
            maxTokens: 1024,
            messages: [
                .init(role: .developer, parts: [.text("Be concise")]),
                .userText("Hello"),
                .init(role: .assistant, parts: [.text("Hi")]),
            ],
            tools: [
                ToolDescriptor.remote(
                    name: "lookup_weather",
                    transport: "weather-api",
                    inputSchema: .object(
                        properties: ["city": .string],
                        required: ["city"]
                    ),
                    description: "Looks up the weather"
                ),
            ]
        )

        let payload = try jsonObject(for: request)
        let messages = try #require(payload["messages"] as? [[String: Any]])
        let tools = try #require(payload["tools"] as? [[String: Any]])

        #expect(payload["model"] as? String == "claude-sonnet-4-20250514")
        #expect(payload["max_tokens"] as? Int == 1024)
        #expect(payload["system"] as? String == "Be concise")
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[1]["role"] as? String == "assistant")
        #expect(tools[0]["name"] as? String == "lookup_weather")
        #expect(tools[0]["description"] as? String == "Looks up the weather")

        let inputSchema = try #require(tools[0]["input_schema"] as? [String: Any])
        #expect(inputSchema["type"] as? String == "object")
        let properties = try #require(inputSchema["properties"] as? [String: Any])
        let city = try #require(properties["city"] as? [String: Any])
        #expect(city["type"] as? String == "string")
    }

    @Test func response_projection_maps_text_and_tool_use_into_agentcore_shapes() throws {
        let response = AnthropicMessageResponse(
            id: "msg_123",
            model: "claude-sonnet-4-20250514",
            role: .assistant,
            content: [
                .text("Checking"),
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
            usage: .init(inputTokens: 12, outputTokens: 8)
        )

        let projection = try response.projectedOutput()

        #expect(projection.messages == [
            AgentMessage(role: .assistant, parts: [.text("Checking")]),
        ])
        #expect(projection.toolCalls == [
            .init(
                callID: "toolu_123",
                invocation: ToolInvocation(
                    toolName: "lookup_weather",
                    arguments: ["city": .string("Paris")]
                )
            ),
        ])
    }

    @Test func client_can_resolve_tool_calls_with_executor() async throws {
        let transport = StubAnthropicTransport(
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
                    content: [
                        .text("Paris is sunny."),
                    ],
                    stopReason: .endTurn,
                    stopSequence: nil,
                    usage: .init(inputTokens: 18, outputTokens: 7)
                ),
            ]
        )
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
        await executor.register(StubWeatherTransport())
        let client = AnthropicMessagesClient(transport: transport)

        let projection = try await client.resolveToolCalls(
            AnthropicMessagesRequest(
                model: "claude-sonnet-4-20250514",
                maxTokens: 1024,
                messages: [.userText("weather in Paris?")],
                tools: [tool]
            ),
            using: executor
        )

        #expect(projection.messages == [
            AgentMessage(role: .assistant, parts: [.text("Paris is sunny.")]),
        ])

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[1].messages.count == 3)

        let assistantContent = requests[1].messages[1].content
        let userContent = requests[1].messages[2].content
        #expect(assistantContent == [
            .toolUse(
                .init(
                    id: "toolu_123",
                    name: "lookup_weather",
                    input: ["city": .string("Paris")]
                )
            ),
        ])
        #expect(userContent == [
            .toolResult(
                .init(
                    toolUseID: "toolu_123",
                    content: "{\"forecast\":\"sunny\"}",
                    isError: false
                )
            ),
        ])
    }

    @Test func transport_retries_retryable_status_codes_using_shared_retry_policy() async throws {
        let session = SequencedAnthropicHTTPSession(
            responses: [
                (
                    """
                    {"error":"busy"}
                    """.data(using: .utf8)!,
                    HTTPURLResponse(
                        url: URL(string: "https://api.anthropic.com/v1/messages")!,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                ),
                (
                    """
                    {
                      "id":"msg_123",
                      "model":"claude-sonnet-4-20250514",
                      "role":"assistant",
                      "content":[{"type":"text","text":"hello"}],
                      "stop_reason":"end_turn",
                      "usage":{"input_tokens":10,"output_tokens":5}
                    }
                    """.data(using: .utf8)!,
                    HTTPURLResponse(
                        url: URL(string: "https://api.anthropic.com/v1/messages")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                ),
            ]
        )
        let transport = URLSessionAnthropicMessagesTransport(
            configuration: .init(
                apiKey: "sk-ant-test",
                transport: .init(
                    retryPolicy: .init(
                        maxAttempts: 2,
                        backoff: .none,
                        retryableStatusCodes: [503]
                    )
                )
            ),
            session: session
        )

        let response = try await transport.createMessage(
            AnthropicMessagesRequest(
                model: "claude-sonnet-4-20250514",
                maxTokens: 1024,
                messages: [.userText("hello")]
            )
        )

        #expect(response.id == "msg_123")
        #expect(await session.requestCount == 2)
    }

    @Test func client_throws_sdk_runtime_error_when_tool_loop_exceeds_iteration_budget() async throws {
        let transport = StubAnthropicTransport(
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
            ]
        )
        let tool = ToolDescriptor.remote(
            name: "lookup_weather",
            transport: "weather-api",
            inputSchema: .object(
                properties: ["city": .string],
                required: ["city"]
            )
        )
        let registry = ToolRegistry()
        try await registry.register(tool)
        let executor = ToolExecutor(registry: registry)
        await executor.register(StubWeatherTransport())
        let client = AnthropicMessagesClient(transport: transport)

        await #expect(
            throws: AgentRuntimeError.toolCallLimitExceeded(provider: .anthropic, maxIterations: 1)
        ) {
            _ = try await client.resolveToolCalls(
                AnthropicMessagesRequest(
                    model: "claude-sonnet-4-20250514",
                    maxTokens: 1024,
                    messages: [.userText("weather in Paris?")],
                    tools: [tool]
                ),
                using: executor,
                maxIterations: 1
            )
        }
    }
}

private actor StubAnthropicTransport: AnthropicMessagesTransport {
    private let responses: [AnthropicMessageResponse]
    private var requests: [AnthropicMessagesRequest] = []
    private var index = 0

    init(responses: [AnthropicMessageResponse]) {
        self.responses = responses
    }

    var recordedRequests: [AnthropicMessagesRequest] {
        requests
    }

    func createMessage(_ request: AnthropicMessagesRequest) async throws -> AnthropicMessageResponse {
        requests.append(request)
        let response = responses[index]
        index += 1
        return response
    }
}

private actor StubWeatherTransport: RemoteToolTransport {
    let transportID = "weather-api"

    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        #expect(invocation.arguments == ["city": .string("Paris")])
        return ToolResult(payload: .object(["forecast": .string("sunny")]))
    }
}

private func jsonObject(for value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private actor RecordingAnthropicHTTPSession: AnthropicHTTPSession {
    let data: Data
    let response: URLResponse
    private(set) var lastRequest: URLRequest?

    init(data: Data, response: URLResponse) {
        self.data = data
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        return (data, response)
    }
}

private actor SequencedAnthropicHTTPSession: AnthropicHTTPSession {
    private let responses: [(Data, URLResponse)]
    private var index = 0
    private(set) var requestCount = 0

    init(responses: [(Data, URLResponse)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        let response = responses[min(index, responses.count - 1)]
        index += 1
        return response
    }
}
