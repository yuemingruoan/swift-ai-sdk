import AgentCore
import AnthropicAgentRuntime
import AnthropicMessagesAPI
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

    @Test func request_encodes_builtin_web_search_tool() throws {
        let request = AnthropicMessagesRequest(
            model: "claude-opus-4-7",
            maxTokens: 1024,
            messages: [.userText("Search for current Swift news")],
            tools: [
                AnthropicTool.webSearch(
                    version: .webSearch20250305,
                    maxUses: 3,
                    allowedDomains: ["example.com"],
                    blockedDomains: ["blocked.example"],
                    userLocation: .init(
                        city: "London",
                        region: "London",
                        country: "GB",
                        timezone: "Europe/London"
                    )
                ),
            ]
        )

        let payload = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        let tools = try #require(payload["tools"] as? [[String: Any]])
        let tool = try #require(tools.first)

        #expect(tool["type"] as? String == "web_search_20250305")
        #expect(tool["name"] as? String == "web_search")
        #expect(tool["max_uses"] as? Int == 3)
        #expect(tool["allowed_domains"] as? [String] == ["example.com"])
        #expect(tool["blocked_domains"] as? [String] == ["blocked.example"])
        let userLocation = try #require(tool["user_location"] as? [String: Any])
        #expect(userLocation["type"] as? String == "approximate")
        #expect(userLocation["city"] as? String == "London")
        #expect(userLocation["region"] as? String == "London")
        #expect(userLocation["country"] as? String == "GB")
        #expect(userLocation["timezone"] as? String == "Europe/London")
    }

    @Test func response_projection_ignores_web_search_server_blocks_but_preserves_raw_content() throws {
        let response = AnthropicMessageResponse(
            id: "msg_websearch",
            model: "claude-opus-4-7",
            role: .assistant,
            content: [
                .serverToolUse(
                    AnthropicServerToolUse(
                        id: "srvtoolu_123",
                        name: "web_search",
                        input: ["query": .string("latest swift news")]
                    )
                ),
                .webSearchToolResult(
                    AnthropicWebSearchToolResult(
                        toolUseID: "srvtoolu_123",
                        content: .results([
                            AnthropicWebSearchResult(
                                url: URL(string: "https://example.com/swift")!,
                                title: "Swift news"
                            ),
                        ])
                    )
                ),
                .text("Swift 6.3 released."),
            ],
            stopReason: .endTurn,
            stopSequence: nil,
            usage: .init(inputTokens: 10, outputTokens: 10)
        )

        let projection = try response.projectedOutput()

        #expect(projection.messages == [
            AgentMessage(role: .assistant, parts: [.text("Swift 6.3 released.")]),
        ])
        #expect(projection.toolCalls.isEmpty)
        #expect(response.content.count == 3)
    }

    @Test func response_decoding_preserves_web_search_citations_and_server_tool_usage() throws {
        let response = try JSONDecoder().decode(
            AnthropicMessageResponse.self,
            from: Data(
                """
                {
                  "id": "msg_citations",
                  "model": "claude-opus-4-6",
                  "role": "assistant",
                  "content": [
                    {
                      "type": "text",
                      "text": "Swift 6.3 is now available.",
                      "citations": [
                        {
                          "type": "web_search_result_location",
                          "url": "https://www.swift.org/blog/",
                          "title": "Swift.org Blog",
                          "encrypted_index": "enc_123",
                          "cited_text": "Swift 6.3 is now available.",
                          "search_result_index": 0
                        }
                      ]
                    }
                  ],
                  "stop_reason": "end_turn",
                  "usage": {
                    "input_tokens": 10,
                    "output_tokens": 12,
                    "server_tool_use": {
                      "web_search_requests": 1
                    }
                  }
                }
                """.utf8
            )
        )

        guard case .textWithCitations(let textBlock) = try #require(response.content.first) else {
            Issue.record("expected textWithCitations block")
            return
        }

        #expect(textBlock.text == "Swift 6.3 is now available.")
        #expect(textBlock.citations?.count == 1)
        #expect(textBlock.citations?.first?.type == "web_search_result_location")
        #expect(textBlock.citations?.first?.encryptedIndex == "enc_123")
        #expect(response.usage.serverToolUse?.webSearchRequests == 1)

        let projection = try response.projectedOutput()
        #expect(projection.messages == [
            AgentMessage(role: .assistant, parts: [.text("Swift 6.3 is now available.")]),
        ])
        #expect(projection.toolCalls.isEmpty)
    }

    @Test func response_decoding_preserves_web_search_error_blocks() throws {
        let response = try JSONDecoder().decode(
            AnthropicMessageResponse.self,
            from: Data(
                """
                {
                  "id": "msg_websearch_error",
                  "model": "claude-opus-4-6",
                  "role": "assistant",
                  "content": [
                    {
                      "type": "server_tool_use",
                      "id": "srvtoolu_err_1",
                      "name": "web_search"
                    },
                    {
                      "type": "web_search_tool_result",
                      "tool_use_id": "srvtoolu_err_1",
                      "content": {
                        "type": "web_search_tool_result_error",
                        "error_code": "max_uses_exceeded"
                      }
                    },
                    {
                      "type": "text",
                      "text": "I could not complete additional searches."
                    }
                  ],
                  "stop_reason": "end_turn",
                  "usage": {
                    "input_tokens": 10,
                    "output_tokens": 12,
                    "server_tool_use": {
                      "web_search_requests": 1
                    }
                  }
                }
                """.utf8
            )
        )

        guard case .webSearchToolResult(let resultBlock) = response.content[1] else {
            Issue.record("expected webSearchToolResult block")
            return
        }
        guard case .error(let errorPayload) = resultBlock.content else {
            Issue.record("expected web search error payload")
            return
        }

        #expect(resultBlock.toolUseID == "srvtoolu_err_1")
        #expect(errorPayload.errorCode == "max_uses_exceeded")

        let projection = try response.projectedOutput()
        #expect(projection.messages == [
            AgentMessage(role: .assistant, parts: [.text("I could not complete additional searches.")]),
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
