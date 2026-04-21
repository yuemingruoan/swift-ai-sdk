import AgentCore
import AgentOpenAI
import AgentOpenAIAuth
import ExampleSupport
import Foundation

@main
enum OpenAIToolLoopExample {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let model = ExampleEnvironment.value("OPENAI_MODEL", default: "gpt-5.4")
        let baseURL = openAIBaseURL(environment: environment)
        let compatibilityProfile = openAICompatibilityProfile(for: baseURL)
        let followUpStrategy = openAIFollowUpStrategy(profile: compatibilityProfile)
        let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
        let input = prompt.isEmpty
            ? "What is the weather in Paris? Use the tool."
            : prompt

        let tool = demoWeatherToolDescriptor()
        let registry = ToolRegistry()
        try await registry.register(tool)
        let executor = ToolExecutor(registry: registry)
        await executor.register(DemoWeatherTransport())

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
                followUpStrategy: followUpStrategy
            )
        } else {
            let apiKey = ExampleEnvironment.require(
                "OPENAI_API_KEY",
                help: "Set OPENAI_API_KEY or OPENAI_ACCESS_TOKEN before running OpenAIToolLoopExample."
            )
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
                followUpStrategy: followUpStrategy
            )
        }

        let runner = OpenAIResponsesTurnRunner(
            client: client,
            configuration: .init(
                model: model,
                tools: [tool],
                toolChoice: .required,
                stream: true
            ),
            executor: executor
        )

        ExampleEventPrinter.printDivider("OpenAI Tool Loop")
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
        let rawValue = ExampleEnvironment.value("OPENAI_COMPAT_PROFILE", default: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch rawValue {
        case "", "auto":
            break
        case "openai":
            return .openAI
        case "newapi", "new-api":
            return .newAPI
        case "sub2api":
            return .sub2api
        case "chatgpt-codex-oauth", "chatgpt_codex_oauth", "chatgpt":
            return .chatGPTCodexOAuth
        default:
            fputs(
                "Invalid OPENAI_COMPAT_PROFILE: \(rawValue). Use auto, openai, newapi, sub2api, or chatgpt-codex-oauth.\n",
                stderr
            )
            Foundation.exit(1)
        }

        switch baseURL.host?.lowercased() {
        case "api.openai.com":
            return .openAI
        case "chatgpt.com":
            return .chatGPTCodexOAuth
        default:
            return .newAPI
        }
    }

    private static func openAIFollowUpStrategy(profile: OpenAICompatibilityProfile) -> OpenAIResponsesFollowUpStrategy {
        let rawValue = ExampleEnvironment.value("OPENAI_RESPONSES_FOLLOW_UP_STRATEGY", default: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch rawValue {
        case "", "auto":
            return profile.responsesFollowUpStrategy
        case "previous-response-id", "previous_response_id", "previousresponseid":
            return .previousResponseID
        case "replay-input", "replay_input", "replayinput":
            return .replayInput
        default:
            fputs(
                "Invalid OPENAI_RESPONSES_FOLLOW_UP_STRATEGY: \(rawValue). Use auto, previous-response-id, or replay-input.\n",
                stderr
            )
            Foundation.exit(1)
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
