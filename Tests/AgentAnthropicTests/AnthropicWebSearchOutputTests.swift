import AnthropicMessagesAPI
import Foundation
import Testing

struct AnthropicWebSearchOutputTests {
    @Test func response_web_search_output_pairs_server_tool_use_result_and_text() {
        let response = AnthropicMessageResponse(
            id: "msg_web_search_output",
            model: "claude-opus-4-6",
            role: .assistant,
            content: [
                .text("Here is what I found.\n\n"),
                .serverToolUse(
                    .init(
                        id: "srvtoolu_1",
                        name: "web_search",
                        input: ["query": .string("latest swift news")]
                    )
                ),
                .webSearchToolResult(
                    .init(
                        toolUseID: "srvtoolu_1",
                        content: .results([
                            .init(
                                url: URL(string: "https://www.swift.org/blog/")!,
                                title: "Swift.org Blog"
                            ),
                        ])
                    )
                ),
                .text("Swift 6.3 is now available."),
            ],
            stopReason: .endTurn,
            stopSequence: nil,
            usage: .init(
                inputTokens: 10,
                outputTokens: 12,
                serverToolUse: .init(webSearchRequests: 1)
            )
        )

        let output = response.webSearchOutput()

        #expect(output.webSearchRequests == 1)
        #expect(output.items.count == 3)

        guard case .text(let introText) = output.items[0] else {
            Issue.record("expected leading text item")
            return
        }
        #expect(introText.text == "Here is what I found.\n\n")

        guard case .search(let exchange) = output.items[1] else {
            Issue.record("expected search exchange item")
            return
        }
        #expect(exchange.toolUseID == "srvtoolu_1")
        #expect(exchange.query == "latest swift news")
        guard case .results(let results)? = exchange.result?.content else {
            Issue.record("expected search results payload")
            return
        }
        #expect(results.count == 1)
        #expect(results.first?.title == "Swift.org Blog")

        guard case .text(let trailingText) = output.items[2] else {
            Issue.record("expected trailing text item")
            return
        }
        #expect(trailingText.text == "Swift 6.3 is now available.")
    }

    @Test func content_web_search_output_items_merge_adjacent_text_and_citations() {
        let items = [
            AnthropicContentBlock.text("Swift 6.3 "),
            .textWithCitations(
                .init(
                    text: "is available.",
                    citations: [
                        .init(
                            type: "web_search_result_location",
                            url: URL(string: "https://www.swift.org/blog/"),
                            title: "Swift.org Blog",
                            encryptedIndex: "enc_123"
                        ),
                    ]
                )
            ),
            .text(" It includes concurrency refinements."),
        ]
            .webSearchOutputItems()

        #expect(items.count == 1)
        guard case .text(let textBlock) = items[0] else {
            Issue.record("expected merged text item")
            return
        }
        #expect(textBlock.text == "Swift 6.3 is available. It includes concurrency refinements.")
        #expect(textBlock.citations?.count == 1)
        #expect(textBlock.citations?.first?.encryptedIndex == "enc_123")
    }

    @Test func response_web_search_output_preserves_error_results() {
        let response = AnthropicMessageResponse(
            id: "msg_web_search_error_output",
            model: "claude-opus-4-6",
            role: .assistant,
            content: [
                .serverToolUse(
                    .init(
                        id: "srvtoolu_err_1",
                        name: "web_search",
                        input: ["query": .string("latest swift release")]
                    )
                ),
                .webSearchToolResult(
                    .init(
                        toolUseID: "srvtoolu_err_1",
                        content: .error(
                            .init(errorCode: "max_uses_exceeded")
                        )
                    )
                ),
            ],
            stopReason: .endTurn,
            stopSequence: nil,
            usage: .init(
                inputTokens: 10,
                outputTokens: 12,
                serverToolUse: .init(webSearchRequests: 1)
            )
        )

        let output = response.webSearchOutput()

        #expect(output.items.count == 1)
        guard case .search(let exchange) = output.items[0] else {
            Issue.record("expected search exchange item")
            return
        }
        #expect(exchange.query == "latest swift release")
        guard case .error(let errorPayload)? = exchange.result?.content else {
            Issue.record("expected web search error payload")
            return
        }
        #expect(errorPayload.errorCode == "max_uses_exceeded")
    }
}
