import AgentCore
import AgentOpenAI
import Foundation
import Testing

struct OpenAIRealtimeWebSocketClientTests {
    @Test func websocket_client_throws_sdk_transport_error_when_not_connected() async {
        let client = OpenAIRealtimeWebSocketClient(
            configuration: .init(apiKey: "sk-test", model: "gpt-realtime"),
            session: StubWebSocketSession(incomingMessages: [])
        )

        await #expect(throws: AgentTransportError.notConnected(provider: .openAI)) {
            _ = try await client.receive()
        }
    }

    @Test func requestBuilder_sets_custom_user_agent_header() throws {
        let builder = OpenAIRealtimeRequestBuilder(
            configuration: .init(
                apiKey: "sk-test",
                model: "gpt-realtime",
                userAgent: "swift-ai-sdk-tests/1.0"
            )
        )
        let request = try builder.makeURLRequest()

        #expect(request.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-tests/1.0")
    }

    @Test func requestBuilder_sets_realtime_endpoint_and_auth_header() throws {
        let builder = OpenAIRealtimeRequestBuilder(
            configuration: .init(apiKey: "sk-test", model: "gpt-realtime")
        )
        let request = try builder.makeURLRequest()

        #expect(request.url?.absoluteString == "wss://api.openai.com/v1/realtime?model=gpt-realtime")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    }

    @Test func requestBuilder_supports_custom_authorization_headers() throws {
        let builder = OpenAIRealtimeRequestBuilder(
            configuration: .init(
                authorizationValue: "Bearer oauth-token",
                model: "gpt-realtime",
                baseURL: URL(string: "wss://chatgpt.com/backend-api/codex/realtime")!,
                additionalHeaders: [
                    "chatgpt-account-id": "acc_123",
                    "originator": "codex_cli_rs",
                ]
            )
        )
        let request = try builder.makeURLRequest()

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
        #expect(request.value(forHTTPHeaderField: "chatgpt-account-id") == "acc_123")
        #expect(request.value(forHTTPHeaderField: "originator") == "codex_cli_rs")
    }

    @Test func websocket_client_sends_and_receives_json_events() async throws {
        let session = StubWebSocketSession(
            incomingMessages: [
                #"{"type":"session.created","session":{"id":"sess_123"}}"#,
            ]
        )
        let client = OpenAIRealtimeWebSocketClient(
            configuration: .init(apiKey: "sk-test", model: "gpt-realtime"),
            session: session
        )

        try await client.connect()
        try await client.send(
            .init(
                type: "session.update",
                payload: [
                    "session": .object([
                        "type": .string("realtime"),
                        "instructions": .string("Be concise"),
                    ]),
                ]
            )
        )

        let event = try await client.receive()
        #expect(event.type == "session.created")
        #expect(event.payload["session"] == .object(["id": .string("sess_123")]))
        let lastSentText = try #require(await session.connection.lastSentText)
        #expect(lastSentText.contains("\"type\":\"session.update\""))
    }

    @Test func websocket_client_can_send_typed_session_update_user_text_and_response_create_events() async throws {
        let session = StubWebSocketSession(incomingMessages: [])
        let client = OpenAIRealtimeWebSocketClient(
            configuration: .init(apiKey: "sk-test", model: "gpt-realtime"),
            session: session
        )

        try await client.connect()
        try await client.updateSession(instructions: "Be concise")
        let sessionUpdateJSON = try #require(await session.connection.lastSentText)
        #expect(sessionUpdateJSON.contains("\"type\":\"session.update\""))
        #expect(sessionUpdateJSON.contains("\"instructions\":\"Be concise\""))

        try await client.sendUserText("hello there")
        let userMessageJSON = try #require(await session.connection.lastSentText)
        #expect(userMessageJSON.contains("\"type\":\"conversation.item.create\""))
        #expect(userMessageJSON.contains("\"text\":\"hello there\""))

        try await client.createResponse()
        let responseCreateJSON = try #require(await session.connection.lastSentText)
        #expect(responseCreateJSON.contains("\"type\":\"response.create\""))
    }

    @Test func structured_realtime_events_encode_expected_payloads() throws {
        let sessionUpdate = try encode(
            OpenAIRealtimeSessionUpdateEvent(
                session: .init(instructions: "Be concise")
            )
        )
        #expect(sessionUpdate["type"] as? String == "session.update")
        let sessionObject = try #require(sessionUpdate["session"] as? [String: Any])
        #expect(sessionObject["instructions"] as? String == "Be concise")

        let userMessage = try encode(
            OpenAIRealtimeConversationItemCreateEvent.userText("hello there")
        )
        #expect(userMessage["type"] as? String == "conversation.item.create")
        let item = try #require(userMessage["item"] as? [String: Any])
        #expect(item["type"] as? String == "message")
        #expect(item["role"] as? String == "user")

        let responseCreate = try encode(OpenAIRealtimeResponseCreateEvent())
        #expect(responseCreate["type"] as? String == "response.create")
    }

    @Test func structured_realtime_events_encode_sdk_tool_descriptors() throws {
        let tool = ToolDescriptor.remote(
            name: "lookup_weather",
            transport: "weather-api",
            inputSchema: .object(
                properties: [
                    "city": .string,
                    "days": .integer,
                ],
                required: ["city"]
            )
        )

        let sessionUpdate = try encode(
            OpenAIRealtimeSessionUpdateEvent(
                session: .init(
                    instructions: "Be concise",
                    tools: [tool],
                    toolChoice: .auto
                )
            )
        )
        let session = try #require(sessionUpdate["session"] as? [String: Any])
        #expect(session["tool_choice"] as? String == "auto")
        let sessionTools = try #require(session["tools"] as? [[String: Any]])
        #expect(sessionTools.count == 1)
        #expect(sessionTools[0]["type"] as? String == "function")
        #expect(sessionTools[0]["name"] as? String == "lookup_weather")

        let responseCreate = try encode(
            OpenAIRealtimeResponseCreateEvent(
                response: .init(
                    tools: [tool],
                    toolChoice: .required
                )
            )
        )
        #expect(responseCreate["type"] as? String == "response.create")
        let response = try #require(responseCreate["response"] as? [String: Any])
        #expect(response["tool_choice"] as? String == "required")
        let responseTools = try #require(response["tools"] as? [[String: Any]])
        #expect(responseTools.count == 1)
        #expect(responseTools[0]["name"] as? String == "lookup_weather")
    }

    @Test func websocket_client_can_resolve_realtime_tool_calls() async throws {
        let toolCallResponse = #"{"type":"response.done","response":{"id":"resp_1","status":"completed","output":[{"type":"function_call","call_id":"call_123","name":"lookup_weather","arguments":"{\"city\":\"Paris\"}","status":"completed"}]}}"#
        let finalResponse = #"{"type":"response.done","response":{"id":"resp_2","status":"completed","output":[{"type":"message","id":"msg_2","role":"assistant","content":[{"type":"output_text","text":"Paris is sunny."}]}]}}"#
        let session = StubWebSocketSession(
            incomingMessages: [
                toolCallResponse,
                finalResponse,
            ]
        )
        let registry = ToolRegistry()
        try await registry.register(
            .remote(
                name: "lookup_weather",
                transport: "weather-api",
                inputSchema: .object(properties: ["city": .string], required: ["city"])
            )
        )
        let executor = ToolExecutor(registry: registry)
        await executor.register(RecordingRealtimeWeatherTransport())
        let client = OpenAIRealtimeWebSocketClient(
            configuration: .init(apiKey: "sk-test", model: "gpt-realtime"),
            session: session
        )

        try await client.connect()
        let events = try await client.receiveUntilTurnFinished(using: executor)

        #expect(events == [
            .toolCall(
                .init(
                    callID: "call_123",
                    invocation: ToolInvocation(
                        toolName: "lookup_weather",
                        arguments: ["city": .string("Paris")]
                    )
                )
            ),
            .messagesCompleted([
                AgentMessage(role: .assistant, parts: [.text("Paris is sunny.")]),
            ]),
        ])

        let sentTexts = await session.connection.sentTexts
        #expect(sentTexts.count == 2)
        #expect(sentTexts[0].contains("\"type\":\"conversation.item.create\""))
        #expect(sentTexts[0].contains("\"type\":\"function_call_output\""))
        #expect(sentTexts[0].contains("\"call_id\":\"call_123\""))
        let parsedOutputEvent = try jsonObject(from: sentTexts[0])
        let outputEvent = try #require(parsedOutputEvent)
        let outputItem = try #require(outputEvent["item"] as? [String: Any])
        #expect(outputItem["output"] as? String == #"{"forecast":"sunny"}"#)
        #expect(sentTexts[1].contains("\"type\":\"response.create\""))
    }
}

private final class StubWebSocketSession: @unchecked Sendable, OpenAIWebSocketSession {
    let connection: StubWebSocketConnection

    init(incomingMessages: [String]) {
        self.connection = StubWebSocketConnection(incomingMessages: incomingMessages)
    }

    func makeConnection(with request: URLRequest) -> any OpenAIWebSocketConnection {
        connection
    }
}

private actor StubWebSocketConnection: OpenAIWebSocketConnection {
    private var incomingMessages: [String]
    private(set) var sentTexts: [String] = []

    var lastSentText: String? {
        sentTexts.last
    }

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

private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func jsonObject(from text: String) throws -> [String: Any]? {
    try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
}

private actor RecordingRealtimeWeatherTransport: RemoteToolTransport {
    let transportID = "weather-api"

    func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        #expect(invocation.toolName == "lookup_weather")
        #expect(invocation.arguments == ["city": .string("Paris")])
        return ToolResult(payload: .object(["forecast": .string("sunny")]))
    }
}
