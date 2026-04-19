import AgentCore
import AgentOpenAI
import Foundation
import Testing

struct OpenAIResponsesClientTests {
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
}

private actor StubResponsesTransport: OpenAIResponsesTransport {
    var lastRequest: OpenAIResponseRequest?

    func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse {
        lastRequest = request
        return OpenAIResponse(id: "resp_new", status: .completed, output: [])
    }
}

private func jsonObject(for request: OpenAIResponseRequest) throws -> [String: Any] {
    let data = try JSONEncoder().encode(request)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}
