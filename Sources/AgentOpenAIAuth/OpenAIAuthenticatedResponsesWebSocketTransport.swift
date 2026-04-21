import AgentOpenAI
import Foundation

public struct OpenAIAuthenticatedResponsesWebSocketRequestBuilder: Sendable {
    public let configuration: OpenAIAuthenticatedAPIConfiguration
    public let tokenProvider: any OpenAITokenProvider

    public init(
        configuration: OpenAIAuthenticatedAPIConfiguration,
        tokenProvider: any OpenAITokenProvider
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
    }

    public func makeURLRequest(clientRequestID: String? = nil) async throws -> URLRequest {
        let tokens = try await tokenProvider.currentTokens()
        return try makeURLRequest(tokens: tokens, clientRequestID: clientRequestID)
    }

    func makeURLRequest(
        tokens: OpenAIAuthTokens,
        clientRequestID: String? = nil
    ) throws -> URLRequest {
        try OpenAIResponsesWebSocketRequestBuilder(
            configuration: try makeConfiguration(
                tokens: tokens,
                clientRequestID: clientRequestID
            )
        ).makeURLRequest()
    }

    func makeConfiguration(
        tokens: OpenAIAuthTokens,
        clientRequestID: String? = nil
    ) throws -> OpenAIResponsesWebSocketConfiguration {
        var headers: [String: String] = [:]

        if let userAgent = configuration.userAgent, !userAgent.isEmpty {
            headers["User-Agent"] = userAgent
        }
        if let acceptLanguage = configuration.acceptLanguage, !acceptLanguage.isEmpty {
            headers["Accept-Language"] = acceptLanguage
        }

        if configuration.compatibilityProfile.requiresChatGPTCodexTransform {
            guard let accountID = tokens.chatGPTAccountID, !accountID.isEmpty else {
                throw OpenAIAuthenticatedTransportError.missingChatGPTAccountID
            }
            headers["chatgpt-account-id"] = accountID
        }

        return OpenAIResponsesWebSocketConfiguration(
            authorizationValue: "Bearer \(tokens.accessToken)",
            baseURL: configuration.baseURL,
            additionalHeaders: headers,
            clientRequestID: clientRequestID
        )
    }
}

public struct URLSessionOpenAIAuthenticatedResponsesWebSocketTransport: OpenAIResponsesStreamingTransport, Sendable {
    private let builder: OpenAIAuthenticatedResponsesWebSocketRequestBuilder
    private let session: any OpenAIWebSocketSession

    public init(
        configuration: OpenAIAuthenticatedAPIConfiguration,
        tokenProvider: any OpenAITokenProvider,
        session: any OpenAIWebSocketSession = URLSession.shared
    ) {
        self.builder = OpenAIAuthenticatedResponsesWebSocketRequestBuilder(
            configuration: configuration,
            tokenProvider: tokenProvider
        )
        self.session = session
    }

    public func streamResponse(_ request: OpenAIResponseRequest) -> AsyncThrowingStream<OpenAIResponseStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let tokens = try await builder.tokenProvider.currentTokens()
                    let configuration = try builder.makeConfiguration(tokens: tokens)
                    let transformed = OpenAIChatGPTRequestTransform(
                        profile: builder.configuration.compatibilityProfile
                    ).transform(request)
                    let transport = URLSessionOpenAIResponsesWebSocketTransport(
                        configuration: configuration,
                        session: session
                    )

                    for try await event in transport.streamResponse(transformed) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
