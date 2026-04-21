import AgentCore
import AgentOpenAIAuth
import AgentOpenAIAuthApple
@testable import AppleHostExampleSupport
import Foundation
import Security
import Testing

@MainActor
struct AppleHostExampleModelTests {
    @Test func tool_call_event_sets_active_tool_name_and_completion_clears_it() async throws {
        let store = try SwiftDataAgentStore.inMemory()
        let keychainClient = KeychainClient(
            add: { _ in errSecSuccess },
            update: { _, _ in errSecSuccess },
            copyMatching: { _, _ in errSecItemNotFound },
            delete: { _ in errSecSuccess }
        )
        let tokenStore = KeychainOpenAITokenStore(
            configuration: .init(service: "tests.apple-host-example"),
            client: keychainClient
        )
        let model = AppleHostExampleModel(store: store, tokenStore: tokenStore)
        var completedMessages: [AgentMessage] = []

        model.apply(
            streamEvent: AgentStreamEvent.toolCall(
                AgentToolCall(
                    callID: "call_123",
                    invocation: ToolInvocation(
                        toolName: "lookup_weather",
                        arguments: ["city": ToolValue.string("Paris")]
                    )
                )
            ),
            completedMessages: &completedMessages
        )

        #expect(model.activeToolName == "lookup_weather")
        #expect(model.latestEventText == "Tool call: lookup_weather")

        model.apply(
            streamEvent: AgentStreamEvent.messagesCompleted([
                AgentMessage(role: .assistant, parts: [.text("Paris is sunny.")]),
            ]),
            completedMessages: &completedMessages
        )

        #expect(model.activeToolName == nil)
        #expect(completedMessages == [
            AgentMessage(role: .assistant, parts: [.text("Paris is sunny.")]),
        ])
    }

    @Test func send_prompt_in_websocket_mode_requires_credentials() async throws {
        let store = try SwiftDataAgentStore.inMemory()
        let keychainClient = KeychainClient(
            add: { _ in errSecSuccess },
            update: { _, _ in errSecSuccess },
            copyMatching: { _, _ in errSecItemNotFound },
            delete: { _ in errSecSuccess }
        )
        let tokenStore = KeychainOpenAITokenStore(
            configuration: .init(service: "tests.apple-host-example"),
            client: keychainClient
        )
        let model = AppleHostExampleModel(store: store, tokenStore: tokenStore)
        model.transportMode = .webSocket
        model.baseURLString = "https://api.openai.com/v1"
        model.realtimeAPIKey = ""
        model.draftPrompt = "hello"

        await model.sendPrompt()

        #expect(model.errorMessage == "Missing realtime credentials.")
        #expect(model.isSending == false)
    }

    @Test func websocket_mode_can_reuse_oauth_access_token() async throws {
        let store = try SwiftDataAgentStore.inMemory()
        let storedTokens = OpenAIAuthTokens(
            accessToken: "oauth-access-token",
            chatGPTAccountID: "acc_123",
            chatGPTPlanType: "plus"
        )
        let tokenStore = KeychainOpenAITokenStore(
            configuration: .init(service: "tests.apple-host-example"),
            client: makeTokenStoreClient(tokens: storedTokens)
        )
        let model = AppleHostExampleModel(store: store, tokenStore: tokenStore)
        model.transportMode = .webSocket
        model.baseURLString = "https://chatgpt.com/backend-api/codex"

        let credentials = try await model.realtimeCredentials()

        #expect(credentials.authorizationValue == "Bearer oauth-access-token")
        #expect(credentials.accountID == "acc_123")
    }

    @Test func websocket_mode_adds_chatgpt_headers_for_oauth_backends() async throws {
        let store = try SwiftDataAgentStore.inMemory()
        let storedTokens = OpenAIAuthTokens(
            accessToken: "oauth-access-token",
            chatGPTAccountID: "acc_123",
            chatGPTPlanType: "plus"
        )
        let tokenStore = KeychainOpenAITokenStore(
            configuration: .init(service: "tests.apple-host-example"),
            client: makeTokenStoreClient(tokens: storedTokens)
        )
        let model = AppleHostExampleModel(store: store, tokenStore: tokenStore)
        model.transportMode = .webSocket
        model.baseURLString = "https://chatgpt.com/backend-api/codex"

        let credentials = try await model.realtimeCredentials()

        #expect(credentials.additionalHeaders["chatgpt-account-id"] == "acc_123")
    }
}

private func makeTokenStoreClient(tokens: OpenAIAuthTokens) -> KeychainClient {
    let data = storedTokenData(from: tokens)
    return KeychainClient(
        add: { _ in errSecSuccess },
        update: { _, _ in errSecSuccess },
        copyMatching: { _, result in
            result?.pointee = data as CFTypeRef
            return errSecSuccess
        },
        delete: { _ in errSecSuccess }
    )
}

private func storedTokenData(from tokens: OpenAIAuthTokens) -> Data {
    try! JSONEncoder().encode(
        StoredOpenAIAuthTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            chatGPTAccountID: tokens.chatGPTAccountID,
            chatGPTPlanType: tokens.chatGPTPlanType,
            expiresAt: tokens.expiresAt
        )
    )
}

private struct StoredOpenAIAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var chatGPTAccountID: String?
    var chatGPTPlanType: String?
    var expiresAt: Date?
}
