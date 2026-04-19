import AgentOpenAI
import Foundation
import Testing

struct OpenAIRealtimeWebSocketClientTests {
    @Test func requestBuilder_sets_realtime_endpoint_and_auth_header() throws {
        let builder = OpenAIRealtimeRequestBuilder(
            configuration: .init(apiKey: "sk-test", model: "gpt-realtime")
        )
        let request = try builder.makeURLRequest()

        #expect(request.url?.absoluteString == "wss://api.openai.com/v1/realtime?model=gpt-realtime")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
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
    var lastSentText: String?

    init(incomingMessages: [String]) {
        self.incomingMessages = incomingMessages
    }

    func connect() async {}

    func send(text: String) async throws {
        lastSentText = text
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
