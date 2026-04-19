import AgentOpenAI
import Foundation
import Testing

struct OpenAIURLSessionTransportTests {
    @Test func requestBuilder_sets_endpoint_headers_and_json_body() throws {
        let builder = OpenAIResponsesRequestBuilder(
            configuration: .init(apiKey: "sk-test", baseURL: URL(string: "https://api.openai.com/v1")!)
        )
        let request = try builder.makeURLRequest(
            for: OpenAIResponseRequest(
                model: "gpt-5.4",
                input: [
                    .init(role: .user, content: [.inputText("hello")]),
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
            {"id":"resp_123","status":"completed","output":[]}
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
                input: [.init(role: .user, content: [.inputText("hello")])]
            )
        )

        #expect(response.id == "resp_123")
        #expect(response.status == OpenAIResponseStatus.completed)
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

        await #expect(throws: OpenAITransportError.unsuccessfulStatusCode(500)) {
            try await transport.createResponse(
                OpenAIResponseRequest(
                    model: "gpt-5.4",
                    input: [.init(role: .user, content: [.inputText("hello")])]
                )
            )
        }
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
