import AgentAnthropic
import AgentCore
import Foundation
import Testing

struct AnthropicContractFixtureTests {
    @Test func request_fixture_matches_encoded_request() throws {
        let request = try AnthropicMessagesRequest(
            model: "claude-sonnet-4-20250514",
            maxTokens: 1024,
            messages: [
                .init(role: .developer, parts: [.text("Be concise")]),
                .userText("Hello"),
                .init(role: .assistant, parts: [.text("Hi")]),
            ],
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
            ]
        )

        let actual = try JSONEncoder().encode(request)
        let expected = try fixtureData(named: "anthropic-request.json")
        #expect(try canonicalJSONString(for: actual) == canonicalJSONString(for: expected))
    }

    @Test func response_fixture_projects_into_provider_neutral_shapes() throws {
        let response = try JSONDecoder().decode(
            AnthropicMessageResponse.self,
            from: fixtureData(named: "anthropic-response.json")
        )

        let projection = try response.projectedOutput()

        #expect(projection.messages == [
            AgentMessage(role: .assistant, parts: [.text("Checking")]),
        ])
        #expect(projection.toolCalls == [
            .init(
                callID: "toolu_123",
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
