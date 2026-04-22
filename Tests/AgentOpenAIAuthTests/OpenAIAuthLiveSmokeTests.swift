import AgentCore
import OpenAIAuthentication
import OpenAIResponsesAPI
import Foundation
import Testing

struct OpenAIAuthLiveSmokeTests {
    @Test func authenticated_transport_can_call_live_backend_when_enabled() async throws {
        guard smokeEnabled("OPENAI_AUTH_LIVE_SMOKE") else {
            return
        }

        let accessToken = try requireEnvironmentValue("OPENAI_ACCESS_TOKEN")
        let accountID = try requireEnvironmentValue("OPENAI_CHATGPT_ACCOUNT_ID")
        let model = ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-5.4"
        let baseURL = try requireURL(
            ProcessInfo.processInfo.environment["OPENAI_AUTH_BASE_URL"]
                ?? "https://chatgpt.com/backend-api/codex"
        )
        let compatibilityProfile = profile(for: baseURL)
        let tokenProvider = OpenAIExternalTokenProvider(
            tokens: OpenAIAuthTokens(
                accessToken: accessToken,
                chatGPTAccountID: accountID,
                chatGPTPlanType: ProcessInfo.processInfo.environment["OPENAI_CHATGPT_PLAN_TYPE"]
            )
        )

        let transport = URLSessionOpenAIAuthenticatedResponsesStreamingTransport(
            configuration: .init(
                baseURL: baseURL,
                compatibilityProfile: compatibilityProfile
            ),
            tokenProvider: tokenProvider
        )

        let request = try OpenAIResponseRequest(
            model: model,
            messages: [.userText("Respond with exactly: OPENAI_AUTH_SMOKE_OK")],
            stream: true
        )
        var outputText = ""
        var completed = false

        for try await event in transport.streamResponse(request) {
            switch event {
            case .outputTextDelta(let delta):
                outputText += delta.delta
            case .outputItemDone(let event):
                outputText += event.item.outputText
            case .responseCompleted:
                completed = true
            case .responseCreated, .responseFailed, .responseIncomplete, .error:
                break
            }
        }

        #expect(completed)
        #expect(outputText.contains("OPENAI_AUTH_SMOKE_OK"))
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
        throw AgentAuthError.missingCredentials(key.lowercased())
    }
    return value
}

private func requireURL(_ rawValue: String) throws -> URL {
    guard let url = URL(string: rawValue) else {
        throw AgentAuthError.invalidConfiguration("openai_auth_base_url")
    }
    return url
}

private func profile(for baseURL: URL) -> OpenAICompatibilityProfile {
    switch baseURL.host?.lowercased() {
    case "chatgpt.com":
        return .chatGPTCodexOAuth
    case "api.openai.com":
        return .openAI
    default:
        return .newAPI
    }
}

private extension OpenAIResponseOutputItem {
    var outputText: String {
        guard case .message(let message) = self else {
            return ""
        }
        return message.content.compactMap { part in
            guard case .outputText(let text) = part else {
                return nil
            }
            return text
        }.joined()
    }
}
