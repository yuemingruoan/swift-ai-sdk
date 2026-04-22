import AnthropicMessagesAPI
import Foundation
import Testing

struct AnthropicWebSearchLiveSmokeTests {
    @Test func anthropic_web_search_live_backend_returns_provider_native_search_blocks_when_enabled() async throws {
        guard smokeEnabled("ANTHROPIC_WEB_SEARCH_LIVE_SMOKE") else {
            return
        }

        let apiKey = try requireEnvironmentValue("ANTHROPIC_API_KEY")
        let baseURL = try requireURL(
            ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"]
                ?? "https://api.anthropic.com/v1"
        )
        let version = ProcessInfo.processInfo.environment["ANTHROPIC_VERSION"] ?? "2023-06-01"
        let model = try requireEnvironmentValue("ANTHROPIC_MODEL")

        let transport = URLSessionAnthropicMessagesTransport(
            configuration: .init(
                apiKey: apiKey,
                baseURL: baseURL,
                version: version,
                transport: .init(timeoutInterval: 20)
            )
        )

        let response = try await transport.createMessage(
            AnthropicMessagesRequest(
                model: model,
                maxTokens: 256,
                messages: [.userText("Search the web for the latest Swift news and answer in one short sentence.")],
                tools: [
                    .webSearch(
                        version: .webSearch20250305,
                        maxUses: 3
                    ),
                ]
            )
        )

        let output = response.webSearchOutput()
        let hasSearchExchange = output.items.contains { item in
            guard case .search(let exchange) = item else {
                return false
            }
            return exchange.serverToolUse != nil || exchange.result != nil
        }

        #expect(hasSearchExchange)
        #expect((response.usage.serverToolUse?.webSearchRequests ?? 0) > 0)
    }
}

private func smokeEnabled(_ key: String) -> Bool {
    let value = ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    return value == "1" || value == "true" || value == "yes"
}

private func requireEnvironmentValue(_ key: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty
    else {
        throw CocoaError(.fileNoSuchFile)
    }
    return value
}

private func requireURL(_ rawValue: String) throws -> URL {
    guard let url = URL(string: rawValue) else {
        throw CocoaError(.fileReadUnsupportedScheme)
    }
    return url
}
