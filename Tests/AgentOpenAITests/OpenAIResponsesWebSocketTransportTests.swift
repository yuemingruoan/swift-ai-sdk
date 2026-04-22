import OpenAIResponsesAPI
import Foundation
import Testing

struct OpenAIResponsesWebSocketTransportTests {
    @Test func request_builder_supports_custom_user_agent() throws {
        let builder = OpenAIResponsesWebSocketRequestBuilder(
            configuration: .init(
                apiKey: "sk-test",
                baseURL: URL(string: "https://api.openai.com/v1")!,
                userAgent: "swift-ai-sdk-tests/1.0"
            )
        )

        let request = try builder.makeURLRequest()

        #expect(request.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-tests/1.0")
    }

    @Test func request_builder_targets_responses_websocket_and_sets_headers() throws {
        let builder = OpenAIResponsesWebSocketRequestBuilder(
            configuration: .init(
                apiKey: "sk-test",
                baseURL: URL(string: "https://api.openai.com/v1")!,
                clientRequestID: "thread_123"
            )
        )

        let request = try builder.makeURLRequest()

        #expect(request.url?.absoluteString == "wss://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "OpenAI-Beta") == "responses_websockets=2026-02-06")
        #expect(request.value(forHTTPHeaderField: "x-client-request-id") == "thread_123")
    }

    @Test func websocket_transport_wraps_response_create_and_decodes_events() async throws {
        let session = StubResponsesWebSocketSession(
            incomingMessages: [
                #"{"type":"response.output_text.delta","item_id":"msg_1","output_index":0,"content_index":0,"delta":"Hello","sequence_number":0}"#,
                #"{"type":"response.completed","response":{"id":"resp_1","status":"completed","output":[{"type":"message","id":"msg_1","role":"assistant","content":[{"type":"output_text","text":"Hello"}]}]}}"#,
            ]
        )
        let transport = URLSessionOpenAIResponsesWebSocketTransport(
            configuration: .init(apiKey: "sk-test"),
            session: session
        )
        let request = try OpenAIResponseRequest(
            model: "gpt-5.4",
            messages: [.userText("hello")],
            stream: true
        )

        var events: [OpenAIResponseStreamEvent] = []
        for try await event in transport.streamResponse(request) {
            events.append(event)
        }

        #expect(events == [
            .outputTextDelta(
                .init(
                    itemID: "msg_1",
                    outputIndex: 0,
                    contentIndex: 0,
                    delta: "Hello",
                    sequenceNumber: 0
                )
            ),
            .responseCompleted(
                .init(
                    id: "resp_1",
                    status: .completed,
                    output: [
                        .message(
                            .init(
                                id: "msg_1",
                                role: .assistant,
                                content: [.outputText("Hello")]
                            )
                        ),
                    ]
                )
            ),
        ])

        let lastSentText = try #require(await session.connection.lastSentText)
        #expect(lastSentText.contains("\"type\":\"response.create\""))
        #expect(lastSentText.contains("\"model\":\"gpt-5.4\""))
        #expect(lastSentText.contains("\"stream\":true"))
    }
}

private final class StubResponsesWebSocketSession: @unchecked Sendable, OpenAIWebSocketSession {
    let connection: StubResponsesWebSocketConnection

    init(incomingMessages: [String]) {
        self.connection = StubResponsesWebSocketConnection(incomingMessages: incomingMessages)
    }

    func makeConnection(with request: URLRequest) -> any OpenAIWebSocketConnection {
        connection
    }
}

private actor StubResponsesWebSocketConnection: OpenAIWebSocketConnection {
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
