import AgentCore
import OpenAIAgentRuntime
import OpenAIResponsesAPI
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

    @Test func request_encodes_builtin_web_search_tool() throws {
        let request = OpenAIResponseRequest(
            model: "gpt-5.4",
            input: [.message(.init(role: .user, content: [.inputText("latest news")]))],
            tools: [
                .webSearch(
                    filters: .init(
                        allowedDomains: ["example.com"],
                        blockedDomains: ["blocked.example"]
                    ),
                    userLocation: .init(
                        country: "GB",
                        city: "London",
                        region: "London"
                    ),
                    externalWebAccess: false
                ),
            ],
            toolChoice: .auto
        )

        let payload = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        let tools = try #require(payload["tools"] as? [[String: Any]])
        let tool = try #require(tools.first)

        #expect(tool["type"] as? String == "web_search")
        let filters = try #require(tool["filters"] as? [String: Any])
        #expect(filters["allowed_domains"] as? [String] == ["example.com"])
        #expect(filters["blocked_domains"] as? [String] == ["blocked.example"])
        let userLocation = try #require(tool["user_location"] as? [String: Any])
        #expect(userLocation["type"] as? String == "approximate")
        #expect(userLocation["country"] as? String == "GB")
        #expect(userLocation["city"] as? String == "London")
        #expect(userLocation["region"] as? String == "London")
        #expect(tool["external_web_access"] as? Bool == false)
    }

    @Test func response_projection_ignores_web_search_calls_but_decodes_raw_output() throws {
        let response = OpenAIResponse(
            id: "resp_websearch",
            status: .completed,
            output: [
                .webSearchCall(
                    .init(
                        id: "ws_123",
                        action: .search(
                            query: "latest swift 6.3 release",
                            queries: ["latest swift 6.3 release"],
                            sources: [.init(type: "url", url: URL(string: "https://example.com")!)]
                        ),
                        status: .completed
                    )
                ),
                .message(
                    .init(
                        id: "msg_123",
                        status: .completed,
                        role: .assistant,
                        content: [.outputText("Swift 6.3 released.")]
                    )
                ),
            ]
        )

        let projection = try response.projectedOutput()

        #expect(projection.messages == [
            AgentMessage(role: .assistant, parts: [.text("Swift 6.3 released.")]),
        ])
        #expect(projection.toolCalls.isEmpty)
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
