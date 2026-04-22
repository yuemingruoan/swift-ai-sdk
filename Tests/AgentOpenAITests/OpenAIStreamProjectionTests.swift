import AgentCore
import OpenAIAgentRuntime
import OpenAIResponsesAPI
import Foundation
import Testing

struct OpenAIStreamProjectionTests {
    @Test func response_projection_maps_into_agent_stream_events() throws {
        let response = OpenAIResponse(
            id: "resp_123",
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

        #expect(try response.projectedOutput().agentStreamEvents() == [
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
                AgentMessage(role: .assistant, parts: [.text("hello")]),
            ]),
        ])
    }

    @Test func streaming_client_projects_sse_into_agent_stream_events() async throws {
        let transport = StubStreamingTransport(
            events: [
                .responseCreated(.init(id: "resp_123", status: .inProgress, output: [])),
                .outputTextDelta(
                    .init(itemID: "msg_123", outputIndex: 0, contentIndex: 0, delta: "Hel", sequenceNumber: 1)
                ),
                .responseCompleted(
                    .init(
                        id: "resp_123",
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
                ),
            ]
        )
        let client = OpenAIResponsesStreamingClient(transport: transport)

        var events: [AgentStreamEvent] = []
        for try await event in client.streamProjectedResponse(
            OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
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

    @Test func streaming_client_projects_completed_output_items_when_completed_response_omits_output() async throws {
        let transport = StubStreamingTransport(
            events: [
                .responseCreated(.init(id: "resp_123", status: .inProgress, output: [])),
                .outputTextDelta(
                    .init(itemID: "msg_123", outputIndex: 0, contentIndex: 0, delta: "Hel", sequenceNumber: 1)
                ),
                .outputItemDone(
                    .init(
                        item: .message(
                            .init(
                                id: "msg_123",
                                status: .completed,
                                role: .assistant,
                                content: [.outputText("hello")]
                            )
                        ),
                        outputIndex: 0,
                        sequenceNumber: 10
                    )
                ),
                .responseCompleted(
                    .init(
                        id: "resp_123",
                        status: .completed,
                        output: []
                    )
                ),
            ]
        )
        let client = OpenAIResponsesStreamingClient(transport: transport)

        var events: [AgentStreamEvent] = []
        for try await event in client.streamProjectedResponse(
            OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
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

    @Test func realtime_event_projection_maps_delta_and_completed_response() throws {
        let deltaEvent = OpenAIRealtimeEvent(
            type: "response.output_text.delta",
            payload: [
                "delta": .string("Hel"),
            ]
        )
        let completedEvent = OpenAIRealtimeEvent(
            type: "response.completed",
            payload: [
                "response": .object([
                    "id": .string("resp_123"),
                    "status": .string("completed"),
                    "output": .array([
                        .object([
                            "type": .string("message"),
                            "id": .string("msg_123"),
                            "role": .string("assistant"),
                            "content": .array([
                                .object([
                                    "type": .string("output_text"),
                                    "text": .string("hello"),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
            ]
        )

        #expect(try deltaEvent.projectedAgentStreamEvents() == [.textDelta("Hel")])
        #expect(try completedEvent.projectedAgentStreamEvents() == [
            .messagesCompleted([
                AgentMessage(role: .assistant, parts: [.text("hello")]),
            ]),
        ])
    }

    @Test func realtime_client_can_receive_projected_stream_events() async throws {
        let session = StubRealtimeSession(
            incomingMessages: [
                #"{"type":"response.output_text.delta","delta":"Hel"}"#,
            ]
        )
        let client = OpenAIRealtimeWebSocketClient(
            configuration: .init(apiKey: "sk-test", model: "gpt-realtime"),
            session: session
        )

        try await client.connect()
        let events = try await client.receiveProjectedEvents()

        #expect(events == [.textDelta("Hel")])
    }
}

private struct StubStreamingTransport: OpenAIResponsesStreamingTransport {
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

private final class StubRealtimeSession: @unchecked Sendable, OpenAIWebSocketSession {
    let connection: StubRealtimeConnection

    init(incomingMessages: [String]) {
        self.connection = StubRealtimeConnection(incomingMessages: incomingMessages)
    }

    func makeConnection(with request: URLRequest) -> any OpenAIWebSocketConnection {
        connection
    }
}

private actor StubRealtimeConnection: OpenAIWebSocketConnection {
    private var incomingMessages: [String]

    init(incomingMessages: [String]) {
        self.incomingMessages = incomingMessages
    }

    func connect() async {}
    func send(text: String) async throws {}

    func receiveText() async throws -> String {
        incomingMessages.removeFirst()
    }

    func cancel() async {}
}
