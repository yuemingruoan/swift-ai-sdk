import AgentCore
import AgentOpenAI
import Foundation
import Testing

struct OpenAIResponsesClientTests {
    @Test func response_projection_maps_message_and_function_call_into_agentcore_shapes() throws {
        let response = OpenAIResponse(
            id: "resp_123",
            status: .completed,
            output: [
                .message(
                    .init(
                        id: "msg_123",
                        status: .completed,
                        role: .assistant,
                        content: [
                            .outputText("hello"),
                            .refusal("cannot do that"),
                        ]
                    )
                ),
                .functionCall(
                    .init(
                        id: "fc_123",
                        callID: "call_123",
                        name: "lookup_weather",
                        arguments: "{\"city\":\"Paris\",\"days\":3}",
                        status: .completed
                    )
                ),
            ]
        )

        let projection = try response.projectedOutput()

        #expect(projection.messages == [
            AgentMessage(
                role: .assistant,
                parts: [
                    .text("hello"),
                    .text("cannot do that"),
                ]
            ),
        ])
        #expect(projection.toolCalls == [
            OpenAIResponseToolCall(
                callID: "call_123",
                invocation: ToolInvocation(
                    toolName: "lookup_weather",
                    arguments: [
                        "city": .string("Paris"),
                        "days": .integer(3),
                    ]
                )
            ),
        ])
    }

    @Test func response_projection_rejects_invalid_function_call_arguments() {
        let response = OpenAIResponse(
            id: "resp_123",
            status: .completed,
            output: [
                .functionCall(
                    .init(
                        callID: "call_123",
                        name: "lookup_weather",
                        arguments: "{invalid json}",
                        status: .completed
                    )
                ),
            ]
        )

        #expect(throws: OpenAIConversionError.invalidFunctionCallArguments("call_123")) {
            _ = try response.projectedOutput()
        }
    }

    @Test func response_projection_rejects_non_object_function_call_arguments() {
        let response = OpenAIResponse(
            id: "resp_123",
            status: .completed,
            output: [
                .functionCall(
                    .init(
                        callID: "call_123",
                        name: "lookup_weather",
                        arguments: "[]",
                        status: .completed
                    )
                ),
            ]
        )

        #expect(throws: OpenAIConversionError.invalidFunctionCallArguments("call_123")) {
            _ = try response.projectedOutput()
        }
    }

    @Test func response_projection_rejects_non_assistant_message_roles() {
        let response = OpenAIResponse(
            id: "resp_123",
            status: .completed,
            output: [
                .message(
                    .init(
                        id: "msg_123",
                        role: .developer,
                        content: [.outputText("internal note")]
                    )
                ),
            ]
        )

        #expect(throws: OpenAIConversionError.unsupportedResponseMessageRole("developer")) {
            _ = try response.projectedOutput()
        }
    }

    @Test func request_builder_encodes_agent_messages_as_openai_input_messages() throws {
        let request = try OpenAIResponseRequest(
            model: "gpt-5.4",
            messages: [
                .init(role: .developer, parts: [.text("be concise")]),
                .init(
                    role: .user,
                    parts: [
                        .text("describe this image"),
                        .image(url: URL(string: "https://example.com/cat.png")!),
                    ]
                ),
            ],
            previousResponseID: "resp_123"
        )

        let payload = try jsonObject(for: request)
        let input = try #require(payload["input"] as? [[String: Any]])

        #expect(payload["model"] as? String == "gpt-5.4")
        #expect(payload["previous_response_id"] as? String == "resp_123")
        #expect(input.count == 2)
        #expect(input[0]["role"] as? String == "developer")
        #expect(input[1]["role"] as? String == "user")

        let userContent = try #require(input[1]["content"] as? [[String: Any]])
        #expect(userContent.count == 2)
        #expect(userContent[0]["type"] as? String == "input_text")
        #expect(userContent[0]["text"] as? String == "describe this image")
        #expect(userContent[1]["type"] as? String == "input_image")
        #expect(userContent[1]["image_url"] as? String == "https://example.com/cat.png")
    }

    @Test func request_builder_rejects_tool_messages() {
        #expect(throws: OpenAIConversionError.unsupportedMessageRole("tool")) {
            _ = try OpenAIResponseRequest(
                model: "gpt-5.4",
                messages: [.init(role: .tool, parts: [.text("tool output")])]
            )
        }
    }

    @Test func request_builder_supports_function_call_output_items() throws {
        let request = OpenAIResponseRequest(
            model: "gpt-5.4",
            input: [
                .functionCallOutput(
                    .init(
                        callID: "call_123",
                        output: .text("{\"ok\":true}")
                    )
                ),
            ]
        )

        let payload = try jsonObject(for: request)
        let input = try #require(payload["input"] as? [[String: Any]])
        #expect(input.count == 1)
        #expect(input[0]["type"] as? String == "function_call_output")
        #expect(input[0]["call_id"] as? String == "call_123")
        #expect(input[0]["output"] as? String == "{\"ok\":true}")
    }

    @Test func structured_request_builder_encodes_mixed_input_items() throws {
        let request = OpenAIResponseRequest(
            model: "gpt-5.4",
            previousResponseID: "resp_prev"
        ) { input in
            input.appendSystemText("follow instructions")
            input.appendUserText("describe this image")
            input.appendUserImage(URL(string: "https://example.com/cat.png")!)
            input.appendFunctionCallOutput(
                callID: "call_123",
                output: .text("{\"ok\":true}")
            )
        }

        let payload = try jsonObject(for: request)
        let input = try #require(payload["input"] as? [[String: Any]])

        #expect(payload["previous_response_id"] as? String == "resp_prev")
        #expect(input.count == 3)
        #expect(input[0]["role"] as? String == "system")

        let userContent = try #require(input[1]["content"] as? [[String: Any]])
        #expect(userContent.count == 2)
        #expect(userContent[0]["text"] as? String == "describe this image")
        #expect(userContent[1]["image_url"] as? String == "https://example.com/cat.png")

        #expect(input[2]["type"] as? String == "function_call_output")
        #expect(input[2]["call_id"] as? String == "call_123")
    }

    @Test func request_builder_encodes_sdk_tool_descriptors_as_responses_function_tools() throws {
        let request = try OpenAIResponseRequest(
            model: "gpt-5.4",
            messages: [.userText("what is the weather in Paris?")],
            tools: [
                ToolDescriptor.remote(
                    name: "lookup_weather",
                    transport: "weather-api",
                    inputSchema: .object(
                        properties: [
                            "city": .string,
                            "days": .integer,
                        ],
                        required: ["city"]
                    )
                ),
            ],
            toolChoice: .required
        )

        let payload = try jsonObject(for: request)
        let tools = try #require(payload["tools"] as? [[String: Any]])
        #expect(payload["tool_choice"] as? String == "required")
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "function")
        #expect(tools[0]["name"] as? String == "lookup_weather")

        let parameters = try #require(tools[0]["parameters"] as? [String: Any])
        #expect(parameters["type"] as? String == "object")
        #expect(parameters["additionalProperties"] as? Bool == false)

        let properties = try #require(parameters["properties"] as? [String: Any])
        let city = try #require(properties["city"] as? [String: Any])
        let days = try #require(properties["days"] as? [String: Any])
        #expect(city["type"] as? String == "string")
        #expect(days["type"] as? String == "integer")
        #expect(parameters["required"] as? [String] == ["city"])
    }

    @Test func client_builds_request_and_delegates_to_transport() async throws {
        let transport = StubResponsesTransport()
        let client = OpenAIResponsesClient(transport: transport)

        let response = try await client.createResponse(
            model: "gpt-5.4",
            messages: [.userText("hello")],
            previousResponseID: "resp_prev"
        )

        #expect(response.id == "resp_new")
        #expect(response.status == .completed)

        let lastRequest = try #require(await transport.lastRequest)
        #expect(lastRequest.model == "gpt-5.4")
        #expect(lastRequest.previousResponseID == "resp_prev")
        #expect(lastRequest.input.count == 1)
    }

    @Test func client_can_return_projected_output() async throws {
        let transport = StubResponsesTransport(
            response: OpenAIResponse(
                id: "resp_projected",
                status: .completed,
                output: [
                    .message(
                        .init(
                            id: "msg_123",
                            role: .assistant,
                            content: [.outputText("hello")]
                        )
                    ),
                    .functionCall(
                        .init(
                            callID: "call_123",
                            name: "lookup_weather",
                            arguments: "{\"city\":\"Paris\"}"
                        )
                    ),
                ]
            )
        )
        let client = OpenAIResponsesClient(transport: transport)

        let projection = try await client.createProjectedResponse(
            model: "gpt-5.4",
            messages: [.userText("hello")]
        )

        #expect(projection.messages == [
            AgentMessage(role: .assistant, parts: [.text("hello")]),
        ])
        #expect(projection.toolCalls == [
            OpenAIResponseToolCall(
                callID: "call_123",
                invocation: ToolInvocation(
                    toolName: "lookup_weather",
                    arguments: ["city": .string("Paris")]
                )
            ),
        ])
    }

    @Test func unified_client_api_returns_non_streaming_projection_when_stream_is_false() async throws {
        let transport = StubResponsesTransport(
            response: OpenAIResponse(
                id: "resp_projected",
                status: .completed,
                output: [
                    .message(
                        .init(
                            id: "msg_123",
                            role: .assistant,
                            content: [.outputText("hello")]
                        )
                    ),
                ]
            )
        )
        let client = OpenAIResponsesClient(
            transport: transport,
            streamingTransport: StubResponsesStreamingTransport(events: [])
        )

        var events: [AgentStreamEvent] = []
        for try await event in try client.projectedResponseEvents(
            model: "gpt-5.4",
            messages: [AgentMessage.userText("hello")],
            stream: false
        ) {
            events.append(event)
        }

        #expect(events == [
            .messagesCompleted([
                AgentMessage(role: .assistant, parts: [.text("hello")]),
            ]),
        ])
    }

    @Test func unified_client_api_uses_streaming_transport_when_stream_is_true() async throws {
        let client = OpenAIResponsesClient(
            transport: StubResponsesTransport(),
            streamingTransport: StubResponsesStreamingTransport(
                events: [
                    OpenAIResponseStreamEvent.outputTextDelta(
                        OpenAIResponseTextDeltaEvent(
                            itemID: "msg_123",
                            outputIndex: 0,
                            contentIndex: 0,
                            delta: "Hel",
                            sequenceNumber: 1
                        )
                    ),
                    OpenAIResponseStreamEvent.responseCompleted(
                        OpenAIResponse(
                            id: "resp_123",
                            status: OpenAIResponseStatus.completed,
                            output: [
                                OpenAIResponseOutputItem.message(
                                    OpenAIResponseMessage(
                                        id: "msg_123",
                                        role: OpenAIInputMessageRole.assistant,
                                        content: [OpenAIResponseMessageContent.outputText("hello")]
                                    )
                                ),
                            ]
                        )
                    ),
                ]
            )
        )

        var events: [AgentStreamEvent] = []
        for try await event in try client.projectedResponseEvents(
            model: "gpt-5.4",
            messages: [AgentMessage.userText("hello")],
            stream: true
        ) {
            events.append(event)
        }

        #expect(events == [
            .textDelta("Hel"),
            .messagesCompleted([
                AgentMessage(role: .assistant, parts: [.text("hello")]),
            ]),
        ])
    }

    @Test func client_can_resolve_tool_calls_with_executor() async throws {
        let tool = ToolDescriptor.remote(
            name: "lookup_weather",
            transport: "weather-api",
            inputSchema: .object(
                properties: ["city": .string],
                required: ["city"]
            )
        )
        let transport = SequencedResponsesTransport(
            responses: [
                OpenAIResponse(
                    id: "resp_1",
                    status: .completed,
                    output: [
                        .functionCall(
                            .init(
                                callID: "call_123",
                                name: "lookup_weather",
                                arguments: "{\"city\":\"Paris\"}",
                                status: .completed
                            )
                        ),
                    ]
                ),
                OpenAIResponse(
                    id: "resp_2",
                    status: .completed,
                    output: [
                        .message(
                            .init(
                                id: "msg_123",
                                role: .assistant,
                                content: [.outputText("Paris is sunny.")]
                            )
                        ),
                    ]
                ),
            ]
        )
        let registry = ToolRegistry()
        try await registry.register(tool)
        let executor = ToolExecutor(registry: registry)
        await executor.register(RecordingWeatherRemoteTransport())

        let client = OpenAIResponsesClient(transport: transport)
        let projection = try await client.resolveToolCalls(
            try OpenAIResponseRequest(
                model: "gpt-5.4",
                messages: [.userText("what is the weather in Paris?")],
                tools: [tool],
                toolChoice: .required
            ),
            using: executor
        )

        #expect(projection.toolCalls.isEmpty)
        #expect(projection.messages == [
            AgentMessage(role: .assistant, parts: [.text("Paris is sunny.")]),
        ])

        let requests = await transport.recordedRequests
        #expect(requests.count == 2)
        #expect(requests[0].tools?.map(\.name) == ["lookup_weather"])
        #expect(requests[0].toolChoice == .required)
        #expect(requests[1].previousResponseID == "resp_1")
        #expect(requests[1].tools?.map(\.name) == ["lookup_weather"])
        #expect(requests[1].toolChoice == nil)

        let followUpPayload = try jsonObject(for: requests[1])
        let followUpInput = try #require(followUpPayload["input"] as? [[String: Any]])
        #expect(followUpInput.count == 1)
        #expect(followUpInput[0]["type"] as? String == "function_call_output")
        #expect(followUpInput[0]["call_id"] as? String == "call_123")
        #expect(followUpInput[0]["output"] as? String == #"{"forecast":"sunny"}"#)
    }
}

private struct StubResponsesStreamingTransport: OpenAIResponsesStreamingTransport {
    let events: [OpenAIResponseStreamEvent]

    func streamResponse(_ request: OpenAIResponseRequest) -> AsyncThrowingStream<OpenAIResponseStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private actor StubResponsesTransport: OpenAIResponsesTransport {
    var lastRequest: OpenAIResponseRequest?
    let response: OpenAIResponse

    init(
        response: OpenAIResponse = OpenAIResponse(
            id: "resp_new",
            status: .completed,
            output: []
        )
    ) {
        self.response = response
    }

    func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse {
        lastRequest = request
        return response
    }
}

private actor SequencedResponsesTransport: OpenAIResponsesTransport {
    private let responses: [OpenAIResponse]
    private var index = 0
    private var requests: [OpenAIResponseRequest] = []

    init(responses: [OpenAIResponse]) {
        self.responses = responses
    }

    var recordedRequests: [OpenAIResponseRequest] {
        requests
    }

    func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse {
        requests.append(request)
        let response = responses[index]
        index += 1
        return response
    }
}

private actor RecordingWeatherRemoteTransport: RemoteToolTransport {
    let transportID = "weather-api"

    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        #expect(invocation.toolName == "lookup_weather")
        #expect(invocation.arguments == ["city": .string("Paris")])
        return ToolResult(payload: .object(["forecast": .string("sunny")]))
    }
}

private func jsonObject(for request: OpenAIResponseRequest) throws -> [String: Any] {
    let data = try JSONEncoder().encode(request)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}
