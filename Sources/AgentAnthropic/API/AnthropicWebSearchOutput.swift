import Foundation

/// Structured provider-native view of Anthropic web-search output blocks.
public struct AnthropicWebSearchOutput: Equatable, Sendable {
    public var items: [AnthropicWebSearchOutputItem]
    public var webSearchRequests: Int?

    /// Creates a structured Anthropic web-search output summary.
    public init(
        items: [AnthropicWebSearchOutputItem],
        webSearchRequests: Int? = nil
    ) {
        self.items = items
        self.webSearchRequests = webSearchRequests
    }
}

/// Ordered output item emitted while Anthropic handles built-in web search.
public enum AnthropicWebSearchOutputItem: Equatable, Sendable {
    case text(AnthropicTextBlock)
    case search(AnthropicWebSearchExchange)
}

/// Pairing of a web-search server-tool invocation with its eventual result block.
public struct AnthropicWebSearchExchange: Equatable, Sendable {
    public var serverToolUse: AnthropicServerToolUse?
    public var result: AnthropicWebSearchToolResult?

    /// Creates a provider-native Anthropic web-search exchange.
    public init(
        serverToolUse: AnthropicServerToolUse? = nil,
        result: AnthropicWebSearchToolResult? = nil
    ) {
        self.serverToolUse = serverToolUse
        self.result = result
    }

    /// Returns the provider-generated tool-use identifier when available.
    public var toolUseID: String? {
        serverToolUse?.id ?? result?.toolUseID
    }

    /// Returns the raw query string passed to the built-in web-search tool when available.
    public var query: String? {
        guard case .string(let query) = serverToolUse?.input["query"] else {
            return nil
        }
        return query
    }
}

public extension AnthropicMessageResponse {
    /// Extracts provider-native Anthropic web-search output from the response content blocks.
    ///
    /// The returned structure preserves official `server_tool_use` and `web_search_tool_result`
    /// blocks, while coalescing adjacent text blocks into a simpler ordered view for hosts that
    /// want Claude Code-style search summaries without dropping raw provider fields.
    func webSearchOutput(
        webSearchToolName: String = "web_search"
    ) -> AnthropicWebSearchOutput {
        AnthropicWebSearchOutput(
            items: content.webSearchOutputItems(webSearchToolName: webSearchToolName),
            webSearchRequests: usage.serverToolUse?.webSearchRequests
        )
    }
}

public extension Array where Element == AnthropicContentBlock {
    /// Extracts ordered Anthropic web-search output items from raw content blocks.
    func webSearchOutputItems(
        webSearchToolName: String = "web_search"
    ) -> [AnthropicWebSearchOutputItem] {
        var items: [AnthropicWebSearchOutputItem] = []
        var exchangeIndicesByToolUseID: [String: Int] = [:]

        for block in self {
            switch block {
            case .text(let text):
                appendTextBlock(
                    AnthropicTextBlock(text: text),
                    into: &items
                )

            case .textWithCitations(let textBlock):
                appendTextBlock(textBlock, into: &items)

            case .serverToolUse(let serverToolUse):
                guard serverToolUse.name == webSearchToolName else {
                    continue
                }
                if let index = exchangeIndicesByToolUseID[serverToolUse.id] {
                    guard case .search(var exchange) = items[index] else {
                        continue
                    }
                    exchange.serverToolUse = serverToolUse
                    items[index] = .search(exchange)
                } else {
                    items.append(
                        .search(
                            AnthropicWebSearchExchange(
                                serverToolUse: serverToolUse
                            )
                        )
                    )
                    exchangeIndicesByToolUseID[serverToolUse.id] = items.endIndex - 1
                }

            case .webSearchToolResult(let result):
                if let index = exchangeIndicesByToolUseID[result.toolUseID] {
                    guard case .search(var exchange) = items[index] else {
                        continue
                    }
                    exchange.result = result
                    items[index] = .search(exchange)
                } else {
                    items.append(
                        .search(
                            AnthropicWebSearchExchange(
                                result: result
                            )
                        )
                    )
                    exchangeIndicesByToolUseID[result.toolUseID] = items.endIndex - 1
                }

            case .toolUse, .toolResult, .thinking:
                continue
            }
        }

        return items
    }
}

private func appendTextBlock(
    _ textBlock: AnthropicTextBlock,
    into items: inout [AnthropicWebSearchOutputItem]
) {
    guard !textBlock.text.isEmpty || !(textBlock.citations?.isEmpty ?? true) else {
        return
    }

    guard let lastItem = items.last else {
        items.append(.text(textBlock))
        return
    }

    guard case .text(let previousTextBlock) = lastItem else {
        items.append(.text(textBlock))
        return
    }

    let mergedCitations = mergeCitations(
        previousTextBlock.citations,
        textBlock.citations
    )
    items[items.endIndex - 1] = .text(
        AnthropicTextBlock(
            text: previousTextBlock.text + textBlock.text,
            citations: mergedCitations
        )
    )
}

private func mergeCitations(
    _ lhs: [AnthropicTextCitation]?,
    _ rhs: [AnthropicTextCitation]?
) -> [AnthropicTextCitation]? {
    let merged = (lhs ?? []) + (rhs ?? [])
    return merged.isEmpty ? nil : merged
}
