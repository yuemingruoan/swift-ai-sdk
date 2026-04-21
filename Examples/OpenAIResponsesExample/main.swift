import AgentCore
import AgentOpenAI
import AgentOpenAIAuth
import ExampleSupport
import Foundation

@main
enum OpenAIResponsesExample {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let model = environment["OPENAI_MODEL"] ?? "gpt-5.4"
        let baseURL = openAIBaseURL(environment: environment)
        let compatibilityProfile = openAICompatibilityProfile(for: baseURL)
        let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
        let input = prompt.isEmpty ? "Write one sentence about Swift concurrency." : prompt

        let client: OpenAIResponsesClient
        if let accessToken = environment["OPENAI_ACCESS_TOKEN"], !accessToken.isEmpty {
            let tokenProvider = OpenAIExternalTokenProvider(
                tokens: OpenAIAuthTokens(
                    accessToken: accessToken,
                    chatGPTAccountID: nonEmpty(environment["OPENAI_CHATGPT_ACCOUNT_ID"]),
                    chatGPTPlanType: nonEmpty(environment["OPENAI_CHATGPT_PLAN_TYPE"])
                )
            )
            let configuration = OpenAIAuthenticatedAPIConfiguration(
                baseURL: baseURL,
                compatibilityProfile: compatibilityProfile
            )
            client = OpenAIResponsesClient(
                transport: URLSessionOpenAIAuthenticatedResponsesTransport(
                    configuration: configuration,
                    tokenProvider: tokenProvider
                ),
                streamingTransport: URLSessionOpenAIAuthenticatedResponsesStreamingTransport(
                    configuration: configuration,
                    tokenProvider: tokenProvider
                ),
                followUpStrategy: compatibilityProfile.responsesFollowUpStrategy
            )
        } else {
            guard let apiKey = environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
                fputs("Set OPENAI_API_KEY or OPENAI_ACCESS_TOKEN before running this example.\n", stderr)
                Foundation.exit(1)
            }

            let transport = URLSessionOpenAIResponsesTransport(
                configuration: .init(
                    apiKey: apiKey,
                    baseURL: baseURL
                )
            )
            let streamingTransport = URLSessionOpenAIResponsesStreamingTransport(
                configuration: .init(
                    apiKey: apiKey,
                    baseURL: baseURL
                )
            )
            client = OpenAIResponsesClient(
                transport: transport,
                streamingTransport: streamingTransport,
                followUpStrategy: compatibilityProfile.responsesFollowUpStrategy
            )
        }
        let runner = OpenAIResponsesTurnRunner(
            client: client,
            configuration: .init(
                model: model,
                stream: true
            )
        )

        for try await event in try runner.runTurn(input: [.userText(input)]) {
            ExampleEventPrinter.printEvent(event)
        }
    }

    private static func openAIBaseURL(environment: [String: String]) -> URL {
        let hasAccessToken = nonEmpty(environment["OPENAI_ACCESS_TOKEN"]) != nil
        let defaultValue = hasAccessToken
            ? "https://chatgpt.com/backend-api/codex"
            : "https://api.openai.com/v1"
        return ExampleEnvironment.url("OPENAI_BASE_URL", default: defaultValue)
    }

    private static func openAICompatibilityProfile(for baseURL: URL) -> OpenAICompatibilityProfile {
        switch baseURL.host?.lowercased() {
        case "api.openai.com":
            return .openAI
        case "chatgpt.com":
            return .chatGPTCodexOAuth
        default:
            return .newAPI
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
