import AgentCore
import AgentOpenAI
import AgentOpenAIAuth
import AgentOpenAIAuthApple
import AgentPersistence
import Foundation
import Observation

public struct AppleHostExampleSessionSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let turnCount: Int

    public init(id: String, title: String, detail: String, turnCount: Int) {
        self.id = id
        self.title = title
        self.detail = detail
        self.turnCount = turnCount
    }
}

public struct AppleHostExampleEventLogEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

public enum AppleHostExampleAuthState: Equatable, Sendable {
    case signedOut
    case waitingForBrowserCallback
    case signedIn(accountID: String?, planType: String?)
}

@MainActor
@Observable
public final class AppleHostExampleModel {
    public var authState: AppleHostExampleAuthState = .signedOut
    public var transportMode: AppleHostExampleTransportMode = .responses
    public var sessions: [AppleHostExampleSessionSummary] = []
    public var selectedSessionID: String?
    public var conversationState = AgentConversationState(sessionID: UUID().uuidString)
    public var draftPrompt = ""
    public var modelName = AppleHostExampleDefaults.modelName
    public var baseURLString = AppleHostExampleDefaults.baseURLString
    public var realtimeAPIKey = ""
    public var allowedWorkspaceID = ""
    public var eventLog: [AppleHostExampleEventLogEntry] = []
    public var liveResponseText = ""
    public var activeToolName: String?
    public var inFlightUserText: String?
    public var isSending = false
    public var errorMessage: String?

    @ObservationIgnored private let store: SwiftDataAgentStore
    @ObservationIgnored private let tokenStore: KeychainOpenAITokenStore
    @ObservationIgnored private var pendingBrowserFlow: OpenAIChatGPTBrowserFlow?
    @ObservationIgnored private var pendingBrowserSessionID: String?

    public init(
        store: SwiftDataAgentStore,
        tokenStore: KeychainOpenAITokenStore
    ) {
        self.store = store
        self.tokenStore = tokenStore
    }

    public static func live() throws -> AppleHostExampleModel {
        let store = try SwiftDataAgentStore.persistent()
        let tokenStore = KeychainOpenAITokenStore(
            configuration: .init(
                service: "dev.swift-ai-sdk.apple-host-example",
                account: "chatgpt-auth"
            )
        )
        return AppleHostExampleModel(store: store, tokenStore: tokenStore)
    }

    public var displayedMessages: [AgentMessage] {
        var messages = conversationState.messages
        if let inFlightUserText, !inFlightUserText.isEmpty {
            messages.append(.userText(inFlightUserText))
        }
        if !liveResponseText.isEmpty {
            messages.append(AgentMessage(role: .assistant, parts: [.text(liveResponseText)]))
        }
        return messages
    }

    public var latestEventText: String? {
        eventLog.last?.text
    }

    public var hasRealtimeAPIKey: Bool {
        !resolvedRealtimeAPIKey().isEmpty
    }

    public var hasRealtimeCredentials: Bool {
        if webSocketUsesChatGPTAuth {
            if case .signedIn = authState {
                return true
            }
            return false
        }

        return hasRealtimeAPIKey
    }

    public var webSocketUsesChatGPTAuth: Bool {
        guard let baseURL = URL(string: baseURLString) else {
            return false
        }
        return compatibilityProfile(for: baseURL).requiresChatGPTCodexTransform
    }

    public func bootstrap() async {
        do {
            try await refreshAuthState()
            try await refreshSessions()
            if let first = sessions.first {
                try await selectSession(id: first.id)
            }
        } catch {
            setError(error)
        }
    }

    public func createSession() {
        let sessionID = UUID().uuidString.lowercased()
        selectedSessionID = sessionID
        conversationState = AgentConversationState(sessionID: sessionID)
        liveResponseText = ""
        activeToolName = nil
        inFlightUserText = nil
    }

    public func selectSession(id: String) async throws {
        let state = try await store.conversationState(sessionID: id) ?? AgentConversationState(sessionID: id)
        selectedSessionID = id
        conversationState = state
        liveResponseText = ""
        activeToolName = nil
        inFlightUserText = nil
    }

    public func startBrowserLogin() async -> URL? {
        do {
            let configuration = OpenAIChatGPTOAuthConfiguration(
                browserRedirectURL: AppleHostExampleDefaults.redirectURL,
                allowedWorkspaceID: nonEmpty(allowedWorkspaceID)
            )
            let flow = OpenAIChatGPTBrowserFlow(configuration: configuration)
            let session = try await flow.startAuthorization(method: .browser)
            guard let authorizationURL = session.authorizationURL else {
                throw OpenAIChatGPTOAuthError.invalidResponse
            }

            cancelPendingBrowserLogin()
            pendingBrowserFlow = flow
            pendingBrowserSessionID = session.sessionID
            authState = .waitingForBrowserCallback
            appendLog("Prepared browser login for \(authorizationURL.absoluteString)")

            errorMessage = nil
            return authorizationURL
        } catch {
            setError(error)
            return nil
        }
    }

    public func completeBrowserLogin(with callbackURL: URL) async {
        guard let sessionID = pendingBrowserSessionID,
              let flow = pendingBrowserFlow
        else {
            setError(OpenAIChatGPTOAuthError.unknownAuthorizationSession)
            return
        }

        do {
            let tokens = try await flow.completeAuthorization(
                sessionID: sessionID,
                callbackURL: callbackURL
            )
            try await tokenStore.saveTokens(tokens)
            finishBrowserLogin(tokens)
        } catch {
            cancelPendingBrowserLogin()
            authState = .signedOut
            setError(error)
        }
    }

    public func cancelBrowserLogin() {
        cancelPendingBrowserLogin()
        if case .waitingForBrowserCallback = authState {
            authState = .signedOut
        }
    }

    public func signOut() async {
        do {
            cancelPendingBrowserLogin()
            try await tokenStore.clearTokens()
            authState = .signedOut
            appendLog("Cleared stored ChatGPT tokens from Keychain.")
            errorMessage = nil
        } catch {
            setError(error)
        }
    }

    public func sendPrompt() async {
        let prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else {
            return
        }

        do {
            errorMessage = nil
            if selectedSessionID == nil {
                createSession()
            }

            let sessionID = try requireSessionID()
            let input = [AgentMessage.userText(prompt)]
            let sessionRunner = try await makeSessionRunner()

            draftPrompt = ""
            inFlightUserText = prompt
            liveResponseText = ""
            activeToolName = nil
            isSending = true

            var completedMessages: [AgentMessage] = []
            for try await event in try sessionRunner.runTurn(
                state: conversationState,
                input: input
            ) {
                switch event {
                case .event(let streamEvent):
                    apply(streamEvent: streamEvent, completedMessages: &completedMessages)
                case .stateUpdated(let updatedState):
                    conversationState = updatedState
                    inFlightUserText = nil
                    liveResponseText = ""
                    activeToolName = nil
                    try await persistTurn(
                        sessionID: sessionID,
                        input: input,
                        output: completedMessages
                    )
                    try await refreshSessions(select: sessionID)
                }
            }

            isSending = false
        } catch {
            isSending = false
            setError(error)
        }
    }

    public func loadDemoPrompt(_ value: String) {
        draftPrompt = value
    }

    public func browserLoginDidFail(_ error: Error) {
        cancelPendingBrowserLogin()
        authState = .signedOut
        setError(error)
    }

    private func finishBrowserLogin(_ tokens: OpenAIAuthTokens) {
        cancelPendingBrowserLogin()
        authState = .signedIn(
            accountID: tokens.chatGPTAccountID,
            planType: tokens.chatGPTPlanType
        )
        appendLog("Saved ChatGPT OAuth tokens to Keychain.")
        errorMessage = nil
    }

    private func cancelPendingBrowserLogin() {
        pendingBrowserSessionID = nil
        pendingBrowserFlow = nil
    }
}

extension AppleHostExampleModel {
    func apply(
        streamEvent event: AgentStreamEvent,
        completedMessages: inout [AgentMessage]
    ) {
        switch event {
        case .textDelta(let delta):
            liveResponseText += delta
        case .toolCall(let call):
            activeToolName = call.invocation.toolName
            appendLog("Tool call: \(call.invocation.toolName)")
        case .messagesCompleted(let messages):
            activeToolName = nil
            completedMessages = messages
        case .turnCompleted(let turn):
            activeToolName = nil
            appendLog("Turn completed for session \(turn.sessionID)")
        }
    }

    func realtimeCredentials() async throws -> AppleHostExampleRealtimeCredentials {
        let baseURL = try url(from: baseURLString)
        let profile = compatibilityProfile(for: baseURL)
        if !profile.requiresChatGPTCodexTransform {
            guard let apiKey = nonEmpty(resolvedRealtimeAPIKey()) else {
                throw AppleHostExampleRuntimeError.missingRealtimeCredentials
            }
            return AppleHostExampleRealtimeCredentials(
                authorizationValue: "Bearer \(apiKey)"
            )
        }

        guard let tokens = try await tokenStore.loadTokens(),
              let accessToken = nonEmpty(tokens.accessToken)
        else {
            throw AppleHostExampleRuntimeError.missingRealtimeCredentials
        }

        var accountID: String?
        var additionalHeaders: [String: String] = [:]
        guard let rawAccountID = tokens.chatGPTAccountID,
              let candidate = nonEmpty(rawAccountID)
        else {
            throw OpenAIAuthenticatedTransportError.missingChatGPTAccountID
        }
        accountID = candidate
        additionalHeaders["chatgpt-account-id"] = candidate

        return AppleHostExampleRealtimeCredentials(
            authorizationValue: "Bearer \(accessToken)",
            accountID: accountID,
            additionalHeaders: additionalHeaders
        )
    }
}

private extension AppleHostExampleModel {
    func requireSessionID() throws -> String {
        if let selectedSessionID {
            return selectedSessionID
        }
        throw CocoaError(.fileNoSuchFile)
    }

    func makeSessionRunner() async throws -> AppleHostExampleSessionRunner {
        switch transportMode {
        case .responses:
            return try await makeResponsesSessionRunner()
        case .webSocket:
            return try await makeResponsesWebSocketSessionRunner()
        }
    }

    func makeResponsesSessionRunner() async throws -> AppleHostExampleSessionRunner {
        let tokenProvider = OpenAIManagedTokenProvider(
            store: tokenStore,
            refresher: OpenAIChatGPTTokenRefresher()
        )
        let baseURL = try url(from: baseURLString)
        let profile = compatibilityProfile(for: baseURL)
        let configuration = OpenAIAuthenticatedAPIConfiguration(
            baseURL: baseURL,
            compatibilityProfile: profile
        )

        let client = OpenAIResponsesClient(
            transport: URLSessionOpenAIAuthenticatedResponsesTransport(
                configuration: configuration,
                tokenProvider: tokenProvider
            ),
            streamingTransport: URLSessionOpenAIAuthenticatedResponsesStreamingTransport(
                configuration: configuration,
                tokenProvider: tokenProvider
            ),
            followUpStrategy: profile.responsesFollowUpStrategy
        )

        let registry = ToolRegistry()
        let tool = demoWeatherToolDescriptor()
        let executor = ToolExecutor(registry: registry)

        try await registry.register(tool)
        await executor.register(DemoWeatherTransport())

        let runner = OpenAIResponsesTurnRunner(
            client: client,
            configuration: .init(
                model: modelName,
                tools: [tool],
                toolChoice: .auto,
                stream: true
            ),
            executor: executor
        )
        return AppleHostExampleSessionRunner(base: AgentSessionRunner(base: runner))
    }

    func makeResponsesWebSocketSessionRunner() async throws -> AppleHostExampleSessionRunner {
        let baseURL = try url(from: baseURLString)
        let profile = compatibilityProfile(for: baseURL)
        let registry = ToolRegistry()
        let tool = demoWeatherToolDescriptor()
        let executor = ToolExecutor(registry: registry)

        try await registry.register(tool)
        await executor.register(DemoWeatherTransport())

        let client: OpenAIResponsesClient
        if profile.requiresChatGPTCodexTransform {
            _ = try await realtimeCredentials()
            let tokenProvider = OpenAIManagedTokenProvider(
                store: tokenStore,
                refresher: OpenAIChatGPTTokenRefresher()
            )
            let configuration = OpenAIAuthenticatedAPIConfiguration(
                baseURL: baseURL,
                compatibilityProfile: profile
            )
            client = OpenAIResponsesClient(
                transport: URLSessionOpenAIAuthenticatedResponsesTransport(
                    configuration: configuration,
                    tokenProvider: tokenProvider
                ),
                streamingTransport: URLSessionOpenAIAuthenticatedResponsesWebSocketTransport(
                    configuration: configuration,
                    tokenProvider: tokenProvider
                ),
                followUpStrategy: profile.responsesFollowUpStrategy
            )
        } else {
            guard let apiKey = nonEmpty(resolvedRealtimeAPIKey()) else {
                throw AppleHostExampleRuntimeError.missingRealtimeCredentials
            }
            let configuration = OpenAIResponsesWebSocketConfiguration(
                apiKey: apiKey,
                baseURL: baseURL,
                clientRequestID: conversationState.sessionID
            )
            client = OpenAIResponsesClient(
                transport: URLSessionOpenAIResponsesTransport(
                    configuration: .init(
                        apiKey: apiKey,
                        baseURL: baseURL
                    )
                ),
                streamingTransport: URLSessionOpenAIResponsesWebSocketTransport(
                    configuration: configuration
                )
            )
        }

        let runner = OpenAIResponsesTurnRunner(
            client: client,
            configuration: .init(
                model: modelName,
                tools: [tool],
                toolChoice: .auto,
                stream: true
            ),
            executor: executor
        )
        return AppleHostExampleSessionRunner(base: AgentSessionRunner(base: runner))
    }

    func persistTurn(
        sessionID: String,
        input: [AgentMessage],
        output: [AgentMessage]
    ) async throws {
        try await store.saveSession(AgentSession(id: sessionID))
        guard !output.isEmpty else {
            return
        }
        try await store.appendTurn(
            AgentTurn(
                sessionID: sessionID,
                input: input,
                output: output
            )
        )
    }

    func refreshSessions(select sessionID: String? = nil) async throws {
        let persisted = try await store.listSessions()
        var summaries: [AppleHostExampleSessionSummary] = []
        for session in persisted {
            let turns = try await store.turns(forSessionID: session.id)
            let latestText = turns.last?.output.last.flatMap(renderText(from:)) ?? ""
            summaries.append(
                AppleHostExampleSessionSummary(
                    id: session.id,
                    title: session.id,
                    detail: latestText,
                    turnCount: turns.count
                )
            )
        }
        sessions = summaries

        if let sessionID {
            selectedSessionID = sessionID
        }
    }

    func refreshAuthState() async throws {
        if let tokens = try await tokenStore.loadTokens() {
            authState = .signedIn(
                accountID: tokens.chatGPTAccountID,
                planType: tokens.chatGPTPlanType
            )
        } else {
            authState = .signedOut
        }
    }

    func appendLog(_ text: String) {
        eventLog.append(.init(text: text))
    }

    func compatibilityProfile(for baseURL: URL) -> OpenAICompatibilityProfile {
        switch baseURL.host?.lowercased() {
        case "api.openai.com":
            return .openAI
        case "chatgpt.com":
            return .chatGPTCodexOAuth
        default:
            return .newAPI
        }
    }

    func renderText(from message: AgentMessage) -> String {
        message.parts.compactMap { part in
            guard case .text(let text) = part else {
                return nil
            }
            return text
        }.joined(separator: " ")
    }

    func setError(_ error: Error) {
        errorMessage = error.localizedDescription
        activeToolName = nil
        appendLog("Error: \(error.localizedDescription)")
    }

    func url(from rawValue: String) throws -> URL {
        guard let url = URL(string: rawValue) else {
            throw CocoaError(.coderInvalidValue)
        }
        return url
    }

    func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func resolvedRealtimeAPIKey() -> String {
        if let value = nonEmpty(realtimeAPIKey) {
            return value
        }

        let environment = ProcessInfo.processInfo.environment
        let keys = [
            "OPENAI_REALTIME_API_KEY",
            "OPENAI_API_KEY",
        ]

        for key in keys {
            if let value = environment[key].flatMap(nonEmpty) {
                return value
            }
        }

        return ""
    }

}
