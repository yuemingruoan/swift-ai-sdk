import AgentOpenAI
import Foundation
import Testing

struct OpenAIResponsesStreamingTransportTests {
    @Test func requestBuilder_enables_streaming_in_request_body() throws {
        let builder = OpenAIResponsesRequestBuilder(
            configuration: .init(apiKey: "sk-test", baseURL: URL(string: "https://api.openai.com/v1")!)
        )
        let request = try builder.makeStreamingURLRequest(
            for: OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["stream"] as? Bool == true)
    }

    @Test func streaming_transport_decodes_sse_events() async throws {
        let session = StubLineStreamingSession(
            lines: [
                "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_123\",\"status\":\"in_progress\",\"output\":[]}}",
                "",
                "data: {\"type\":\"response.output_text.delta\",\"item_id\":\"msg_123\",\"output_index\":0,\"content_index\":0,\"delta\":\"Hel\",\"sequence_number\":1}",
                "",
                "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_123\",\"status\":\"completed\",\"output\":[]}}",
                "",
            ]
        )
        let transport = URLSessionOpenAIResponsesStreamingTransport(
            configuration: .init(apiKey: "sk-test"),
            session: session
        )

        var events: [OpenAIResponseStreamEvent] = []
        for try await event in transport.streamResponse(
            OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        ) {
            events.append(event)
        }

        #expect(events == [
            OpenAIResponseStreamEvent.responseCreated(
                OpenAIResponse(id: "resp_123", status: .inProgress, output: [])
            ),
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
                OpenAIResponse(id: "resp_123", status: .completed, output: [])
            ),
        ])
    }
}

private actor StubLineStreamingSession: OpenAIHTTPLineStreamingSession {
    let lines: [String]

    init(lines: [String]) {
        self.lines = lines
    }

    func streamLines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (
            AsyncThrowingStream { continuation in
                for line in lines {
                    continuation.yield(line)
                }
                continuation.finish()
            },
            response
        )
    }
}
