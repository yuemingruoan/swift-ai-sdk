import AgentAnthropic
import AgentCore
import Foundation
import Testing

struct AnthropicMessagesStreamingTransportTests {
    @Test func request_builder_enables_streaming_in_request_body() throws {
        let builder = AnthropicMessagesRequestBuilder(
            configuration: .init(apiKey: "sk-ant-test", baseURL: URL(string: "https://api.anthropic.com/v1")!)
        )
        let request = try builder.makeStreamingURLRequest(
            for: AnthropicMessagesRequest(
                model: "claude-sonnet-4-20250514",
                maxTokens: 256,
                messages: [.userText("hello")]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["stream"] as? Bool == true)
        #expect(json["max_tokens"] as? Int == 256)
    }

    @Test func streaming_transport_passes_shared_transport_configuration_to_injected_session() async throws {
        let session = StubAnthropicLineStreamingSession(
            lines: [
                "data: {\"type\":\"message_stop\"}",
                "",
            ]
        )
        let transport = URLSessionAnthropicMessagesStreamingTransport(
            configuration: .init(
                apiKey: "sk-ant-test",
                transport: .init(
                    timeoutInterval: 9,
                    additionalHeaders: ["X-Test-Header": "fixture"],
                    userAgent: "swift-ai-sdk-anthropic-stream-tests/1.0",
                    requestID: "req_ant_stream_123"
                )
            ),
            session: session
        )

        var events: [AnthropicMessageStreamEvent] = []
        for try await event in transport.streamMessage(
            try AnthropicMessagesRequest(
                model: "claude-sonnet-4-20250514",
                maxTokens: 256,
                messages: [.userText("hello")]
            )
        ) {
            events.append(event)
        }

        #expect(events == [.messageStop])
        let requests = await session.recordedRequests
        #expect(requests.count == 1)
        let request = requests[0]
        #expect(request.timeoutInterval == 9)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-anthropic-stream-tests/1.0")
        #expect(request.value(forHTTPHeaderField: "X-Test-Header") == "fixture")
        #expect(request.value(forHTTPHeaderField: "X-Request-Id") == "req_ant_stream_123")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
    }

    @Test func streaming_transport_decodes_message_lifecycle_events() async throws {
        let session = StubAnthropicLineStreamingSession(
            lines: [
                "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_123\",\"model\":\"claude-sonnet-4-20250514\",\"role\":\"assistant\",\"content\":[],\"stop_reason\":\"\",\"stop_sequence\":null,\"usage\":{\"input_tokens\":25,\"output_tokens\":1}}}",
                "",
                "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
                "",
                "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}",
                "",
                "data: {\"type\":\"content_block_stop\",\"index\":0}",
                "",
                "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":15}}",
                "",
                "data: {\"type\":\"message_stop\"}",
                "",
            ]
        )
        let transport = URLSessionAnthropicMessagesStreamingTransport(
            configuration: .init(apiKey: "sk-ant-test"),
            session: session
        )

        var events: [AnthropicMessageStreamEvent] = []
        for try await event in transport.streamMessage(
            try AnthropicMessagesRequest(
                model: "claude-sonnet-4-20250514",
                maxTokens: 256,
                messages: [.userText("hello")]
            )
        ) {
            events.append(event)
        }

        #expect(events == [
            .messageStart(
                .init(
                    message: AnthropicMessageResponse(
                        id: "msg_123",
                        model: "claude-sonnet-4-20250514",
                        role: .assistant,
                        content: [],
                        stopReason: nil,
                        stopSequence: nil,
                        usage: .init(inputTokens: 25, outputTokens: 1)
                    )
                )
            ),
            .contentBlockStart(
                .init(
                    index: 0,
                    contentBlock: .init(type: "text", text: "")
                )
            ),
            .contentBlockDelta(
                .init(
                    index: 0,
                    delta: .init(type: "text_delta", text: "Hello")
                )
            ),
            .contentBlockStop(.init(index: 0)),
            .messageDelta(
                .init(
                    delta: .init(stopReason: .endTurn, stopSequence: nil),
                    usage: .init(outputTokens: 15)
                )
            ),
            .messageStop,
        ])
    }

    @Test func streaming_transport_preserves_unknown_events() async throws {
        let session = StubAnthropicLineStreamingSession(
            lines: [
                "data: {\"type\":\"custom_event\",\"payload\":123}",
                "",
            ]
        )
        let transport = URLSessionAnthropicMessagesStreamingTransport(
            configuration: .init(apiKey: "sk-ant-test"),
            session: session
        )

        var events: [AnthropicMessageStreamEvent] = []
        for try await event in transport.streamMessage(
            try AnthropicMessagesRequest(
                model: "claude-sonnet-4-20250514",
                maxTokens: 256,
                messages: [.userText("hello")]
            )
        ) {
            events.append(event)
        }

        #expect(events == [
            .unknown(type: "custom_event", rawData: #"{"type":"custom_event","payload":123}"#),
        ])
    }

    @Test func streaming_transport_throws_typed_error_for_truncated_payloads() async {
        let session = StubAnthropicLineStreamingSession(
            lines: [
                "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_123\"",
                "",
            ]
        )
        let transport = URLSessionAnthropicMessagesStreamingTransport(
            configuration: .init(apiKey: "sk-ant-test"),
            session: session
        )

        await #expect(throws: AgentStreamError.eventDecodingFailed(provider: .anthropic)) {
            var iterator = transport.streamMessage(
                try AnthropicMessagesRequest(
                    model: "claude-sonnet-4-20250514",
                    maxTokens: 256,
                    messages: [.userText("hello")]
                )
            ).makeAsyncIterator()
            _ = try await iterator.next()
        }
    }
}

private actor StubAnthropicLineStreamingSession: AnthropicHTTPLineStreamingSession {
    let lines: [String]
    private(set) var recordedRequests: [URLRequest] = []

    init(lines: [String]) {
        self.lines = lines
    }

    func streamLines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse) {
        recordedRequests.append(request)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (
            AsyncThrowingStream { continuation in
                let task = Task {
                    for line in lines {
                        if Task.isCancelled { break }
                        continuation.yield(line)
                        try? await Task.sleep(for: .milliseconds(10))
                    }
                    continuation.finish()
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            },
            response
        )
    }
}
