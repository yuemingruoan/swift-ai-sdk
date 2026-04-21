import AgentCore
import AgentOpenAI
import Foundation
import Testing

struct OpenAIURLSessionTransportTests {
    @Test func requestBuilder_applies_shared_transport_configuration() throws {
        let builder = OpenAIResponsesRequestBuilder(
            configuration: .init(
                apiKey: "sk-test",
                transport: .init(
                    timeoutInterval: 12,
                    additionalHeaders: ["X-Test-Header": "fixture"],
                    userAgent: "swift-ai-sdk-tests/2.0",
                    requestID: "req_openai_123"
                )
            )
        )
        let request = try builder.makeURLRequest(
            for: OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [
                    .message(.init(role: .user, content: [.inputText("hello")])),
                ]
            )
        )

        #expect(request.timeoutInterval == 12)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-tests/2.0")
        #expect(request.value(forHTTPHeaderField: "X-Test-Header") == "fixture")
        #expect(request.value(forHTTPHeaderField: "X-Request-Id") == "req_openai_123")
    }

    @Test func requestBuilder_sets_custom_user_agent_header() throws {
        let builder = OpenAIResponsesRequestBuilder(
            configuration: .init(
                apiKey: "sk-test",
                baseURL: URL(string: "https://api.openai.com/v1")!,
                userAgent: "swift-ai-sdk-tests/1.0"
            )
        )
        let request = try builder.makeURLRequest(
            for: OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [
                    .message(.init(role: .user, content: [.inputText("hello")])),
                ]
            )
        )

        #expect(request.value(forHTTPHeaderField: "User-Agent") == "swift-ai-sdk-tests/1.0")
    }

    @Test func requestBuilder_sets_endpoint_headers_and_json_body() throws {
        let builder = OpenAIResponsesRequestBuilder(
            configuration: .init(apiKey: "sk-test", baseURL: URL(string: "https://api.openai.com/v1")!)
        )
        let request = try builder.makeURLRequest(
            for: OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [
                    .message(.init(role: .user, content: [.inputText("hello")])),
                ]
            )
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-5.4")
    }

    @Test func transport_decodes_successful_response() async throws {
        let session = StubHTTPSession(
            data: """
            {
              "id":"resp_123",
              "status":"completed",
              "output":[
                {
                  "type":"message",
                  "id":"msg_123",
                  "status":"completed",
                  "role":"assistant",
                  "content":[
                    {"type":"output_text","text":"hello from model"}
                  ]
                },
                {
                  "type":"function_call",
                  "id":"fc_123",
                  "call_id":"call_123",
                  "name":"lookup_weather",
                  "arguments":"{\\"city\\":\\"Paris\\"}",
                  "status":"completed"
                }
              ]
            }
            """.data(using: .utf8)!,
            response: HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        let transport = URLSessionOpenAIResponsesTransport(
            configuration: .init(apiKey: "sk-test"),
            session: session
        )

        let response = try await transport.createResponse(
            OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        )

        #expect(response.id == "resp_123")
        #expect(response.status == OpenAIResponseStatus.completed)
        #expect(response.output.count == 2)

        if case .message(let message) = response.output[0] {
            #expect(message.id == "msg_123")
            #expect(message.content == [OpenAIResponseMessageContent.outputText("hello from model")])
        } else {
            Issue.record("expected first output item to decode as a message")
        }

        if case .functionCall(let functionCall) = response.output[1] {
            #expect(functionCall.callID == "call_123")
            #expect(functionCall.name == "lookup_weather")
        } else {
            Issue.record("expected second output item to decode as a function call")
        }

        let lastRequest = try #require(await session.lastRequest)
        #expect(lastRequest.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    }

    @Test func transport_throws_for_unsuccessful_status_codes() async {
        let session = StubHTTPSession(
            data: Data(),
            response: HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        let transport = URLSessionOpenAIResponsesTransport(
            configuration: .init(apiKey: "sk-test"),
            session: session
        )

        await #expect(throws: AgentProviderError.unsuccessfulResponse(provider: .openAI, statusCode: 500)) {
            try await transport.createResponse(
                OpenAIResponseRequest(
                    model: "gpt-5.4",
                    input: [.message(.init(role: .user, content: [.inputText("hello")]))]
                )
            )
        }
    }

    @Test func transport_retries_retryable_status_codes_using_shared_retry_policy() async throws {
        let session = SequencedHTTPSession(
            responses: [
                (
                    """
                    {"error":"busy"}
                    """.data(using: .utf8)!,
                    HTTPURLResponse(
                        url: URL(string: "https://api.openai.com/v1/responses")!,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                ),
                (
                    """
                    {
                      "id":"resp_123",
                      "status":"completed",
                      "output":[]
                    }
                    """.data(using: .utf8)!,
                    HTTPURLResponse(
                        url: URL(string: "https://api.openai.com/v1/responses")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                ),
            ]
        )
        let transport = URLSessionOpenAIResponsesTransport(
            configuration: .init(
                apiKey: "sk-test",
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

        let response = try await transport.createResponse(
            OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [.message(.init(role: .user, content: [.inputText("hello")]))]
            )
        )

        #expect(response.id == "resp_123")
        #expect(await session.requestCount == 2)
    }
}

private actor StubHTTPSession: OpenAIHTTPSession {
    let data: Data
    let response: URLResponse
    var lastRequest: URLRequest?

    init(data: Data, response: URLResponse) {
        self.data = data
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        return (data, response)
    }
}

private actor SequencedHTTPSession: OpenAIHTTPSession {
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
