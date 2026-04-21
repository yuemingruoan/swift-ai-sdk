import AgentCore
import AgentOpenAI
import Foundation
import Testing

struct OpenAIContractFixtureTests {
    @Test func request_fixture_matches_encoded_request() throws {
        let request = try OpenAIResponseRequest(
            model: "gpt-5.4",
            messages: [
                .init(role: .developer, parts: [.text("be concise")]),
                .init(
                    role: .user,
                    parts: [
                        .text("Hello"),
                        .image(url: URL(string: "https://example.com/cat.png")!),
                    ]
                ),
            ],
            previousResponseID: "resp_123",
            tools: [
                ToolDescriptor.remote(
                    name: "lookup_weather",
                    transport: "weather-api",
                    inputSchema: .object(
                        properties: ["city": .string],
                        required: ["city"]
                    ),
                    description: "Looks up the weather"
                ),
            ],
            toolChoice: .required
        )

        let actual = try JSONEncoder().encode(request)
        let expected = try fixtureData(named: "openai-request.json")
        #expect(try canonicalJSONString(for: actual) == canonicalJSONString(for: expected))
    }

    @Test func response_fixture_projects_into_provider_neutral_shapes() throws {
        let response = try JSONDecoder().decode(
            OpenAIResponse.self,
            from: fixtureData(named: "openai-response.json")
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
                    arguments: ["city": .string("Paris")]
                )
            ),
        ])
    }
}

private func fixtureData(named name: String) throws -> Data {
    let fileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent(name)
    return try Data(contentsOf: fileURL)
}

private func canonicalJSONString(for data: Data) throws -> String {
    let object = try JSONSerialization.jsonObject(with: data)
    let canonicalData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: canonicalData, as: UTF8.self)
}
