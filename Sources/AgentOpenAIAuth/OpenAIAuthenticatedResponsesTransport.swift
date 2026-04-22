import AgentCore
import OpenAIResponsesAPI
import Foundation

/// Connection settings for ChatGPT/Codex-style authenticated Responses endpoints.
public struct OpenAIAuthenticatedAPIConfiguration: Sendable {
    public var baseURL: URL
    public var compatibilityProfile: OpenAICompatibilityProfile
    public var originator: String?
    public var userAgent: String?
    public var acceptLanguage: String?
    public var transport: AgentHTTPTransportConfiguration

    /// Creates configuration for authenticated ChatGPT/Codex-style Responses endpoints.
    /// - Parameters:
    ///   - baseURL: Base URL for the authenticated Responses endpoint family.
    ///   - compatibilityProfile: Compatibility profile controlling request shaping and headers.
    ///   - originator: Optional `originator` header value for compatible backends.
    ///   - userAgent: Optional `User-Agent` header override.
    ///   - acceptLanguage: Optional `Accept-Language` header override.
    ///   - transport: Shared HTTP transport settings such as timeout, retry policy, headers, and request ID.
    public init(
        baseURL: URL = URL(string: "https://chatgpt.com/backend-api/codex")!,
        compatibilityProfile: OpenAICompatibilityProfile = .chatGPTCodexOAuth,
        originator: String? = "codex_cli_rs",
        userAgent: String? = nil,
        acceptLanguage: String? = nil,
        transport: AgentHTTPTransportConfiguration = .init()
    ) {
        self.baseURL = baseURL
        self.compatibilityProfile = compatibilityProfile
        self.originator = originator
        self.userAgent = userAgent
        self.acceptLanguage = acceptLanguage
        self.transport = transport
    }
}

/// Lower-level builder for authenticated OpenAI-compatible Responses requests.
public struct OpenAIAuthenticatedResponsesRequestBuilder: Sendable {
    public let configuration: OpenAIAuthenticatedAPIConfiguration
    public let tokenProvider: any OpenAITokenProvider

    /// Creates an authenticated request builder.
    /// - Parameters:
    ///   - configuration: HTTP and compatibility settings used for generated requests.
    ///   - tokenProvider: Token provider used to supply bearer tokens for each request.
    public init(
        configuration: OpenAIAuthenticatedAPIConfiguration,
        tokenProvider: any OpenAITokenProvider
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
    }

    /// Builds a non-streaming authenticated request using the provider's current tokens.
    /// - Parameter request: Low-level Responses request payload.
    /// - Returns: A configured authenticated `URLRequest`.
    /// - Throws: An error if tokens cannot be loaded or the request cannot be encoded.
    public func makeURLRequest(for request: OpenAIResponseRequest) async throws -> URLRequest {
        let tokens = try await tokenProvider.currentTokens()
        return try makeURLRequest(for: request, tokens: tokens, streaming: false)
    }

    /// Builds a streaming authenticated request using the provider's current tokens.
    /// - Parameter request: Low-level Responses request payload.
    /// - Returns: A configured authenticated streaming `URLRequest`.
    /// - Throws: An error if tokens cannot be loaded or the request cannot be encoded.
    public func makeStreamingURLRequest(for request: OpenAIResponseRequest) async throws -> URLRequest {
        let tokens = try await tokenProvider.currentTokens()
        return try makeURLRequest(for: request, tokens: tokens, streaming: true)
    }

    func makeURLRequest(
        for request: OpenAIResponseRequest,
        tokens: OpenAIAuthTokens,
        streaming: Bool
    ) throws -> URLRequest {
        let transformed = OpenAIChatGPTRequestTransform(
            profile: configuration.compatibilityProfile
        ).transform(request)
        let endpoint = configuration.baseURL.appendingPathComponent("responses")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(
            streaming ? "text/event-stream" : "application/json",
            forHTTPHeaderField: "Accept"
        )
        if let timeoutInterval = configuration.transport.timeoutInterval {
            urlRequest.timeoutInterval = timeoutInterval
        }

        if let userAgent = configuration.transport.userAgent ?? configuration.userAgent, !userAgent.isEmpty {
            urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        if let acceptLanguage = configuration.acceptLanguage, !acceptLanguage.isEmpty {
            urlRequest.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        }
        if let requestID = configuration.transport.requestID, !requestID.isEmpty {
            urlRequest.setValue(requestID, forHTTPHeaderField: "X-Request-Id")
        }
        for (header, value) in configuration.transport.additionalHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }

        if configuration.compatibilityProfile.requiresChatGPTCodexTransform {
            guard let accountID = tokens.chatGPTAccountID, !accountID.isEmpty else {
                throw AgentAuthError.missingCredentials("chatgpt_account_id")
            }
            urlRequest.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
            urlRequest.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
            if let originator = configuration.originator, !originator.isEmpty {
                urlRequest.setValue(originator, forHTTPHeaderField: "originator")
            }
        }

        urlRequest.httpBody = try JSONEncoder().encode(transformed)
        return urlRequest
    }
}

/// Concrete non-streaming transport for authenticated OpenAI-compatible Responses endpoints.
public struct URLSessionOpenAIAuthenticatedResponsesTransport: OpenAIResponsesTransport, Sendable {
    private let builder: OpenAIAuthenticatedResponsesRequestBuilder
    private let session: any OpenAIHTTPSession

    /// Creates a non-streaming authenticated Responses transport.
    /// - Parameters:
    ///   - configuration: HTTP and compatibility settings used for generated requests.
    ///   - tokenProvider: Token provider used to supply and refresh bearer tokens.
    ///   - session: Injectable HTTP session for transport customization or testing.
    public init(
        configuration: OpenAIAuthenticatedAPIConfiguration,
        tokenProvider: any OpenAITokenProvider,
        session: any OpenAIHTTPSession = URLSession.shared
    ) {
        self.builder = OpenAIAuthenticatedResponsesRequestBuilder(
            configuration: configuration,
            tokenProvider: tokenProvider
        )
        self.session = session
    }

    /// Sends a request and retries once after a 401 by refreshing tokens.
    /// - Parameter request: Low-level Responses request payload.
    /// - Returns: The decoded raw Responses payload.
    /// - Throws: An error if token lookup, refresh, transport execution, or response decoding fails.
    public func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse {
        let retryPolicy = builder.configuration.transport.retryPolicy
        var tokens = try await builder.tokenProvider.currentTokens()
        var refreshedAfterUnauthorized = false
        var attempt = 1

        while true {
            do {
                let urlRequest = try builder.makeURLRequest(
                    for: request,
                    tokens: tokens,
                    streaming: false
                )
                let (data, response) = try await session.data(for: urlRequest)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AgentTransportError.invalidResponse(provider: .openAI)
                }

                if httpResponse.statusCode == 401, !refreshedAfterUnauthorized {
                    tokens = try await builder.tokenProvider.refreshTokens(reason: .unauthorized)
                    refreshedAfterUnauthorized = true
                    continue
                }

                if retryPolicy.shouldRetry(afterAttempt: attempt, statusCode: httpResponse.statusCode) {
                    attempt += 1
                    try await sleepForRetryIfNeeded(retryPolicy.backoff)
                    continue
                }

                return try decodeResponse(data: data, response: response)
            } catch let error as AgentAuthError {
                throw error
            } catch let error as AgentProviderError {
                throw error
            } catch let error as AgentTransportError {
                if retryPolicy.shouldRetry(afterAttempt: attempt) {
                    attempt += 1
                    try await sleepForRetryIfNeeded(retryPolicy.backoff)
                    continue
                }
                throw error
            } catch let error as AgentDecodingError {
                throw error
            } catch {
                let mappedError = AgentTransportError.requestFailed(
                    provider: .openAI,
                    description: String(describing: error)
                )
                if retryPolicy.shouldRetry(afterAttempt: attempt) {
                    attempt += 1
                    try await sleepForRetryIfNeeded(retryPolicy.backoff)
                    continue
                }
                throw mappedError
            }
        }
    }

    private func decodeResponse(data: Data, response: URLResponse) throws -> OpenAIResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentTransportError.invalidResponse(provider: .openAI)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AgentProviderError.unsuccessfulResponse(
                provider: .openAI,
                statusCode: httpResponse.statusCode
            )
        }
        do {
            return try JSONDecoder().decode(OpenAIResponse.self, from: data)
        } catch {
            throw AgentDecodingError.responseBody(
                provider: .openAI,
                description: String(describing: error)
            )
        }
    }
}

/// Concrete SSE transport for authenticated OpenAI-compatible Responses endpoints.
public struct URLSessionOpenAIAuthenticatedResponsesStreamingTransport: OpenAIResponsesStreamingTransport, Sendable {
    private let builder: OpenAIAuthenticatedResponsesRequestBuilder
    private let session: any OpenAIHTTPLineStreamingSession

    /// Creates an authenticated SSE Responses transport.
    /// - Parameters:
    ///   - configuration: HTTP and compatibility settings used for generated requests.
    ///   - tokenProvider: Token provider used to supply and refresh bearer tokens.
    ///   - session: Injectable line-streaming session for transport customization or testing.
    public init(
        configuration: OpenAIAuthenticatedAPIConfiguration,
        tokenProvider: any OpenAITokenProvider,
        session: any OpenAIHTTPLineStreamingSession = URLSession.shared
    ) {
        self.builder = OpenAIAuthenticatedResponsesRequestBuilder(
            configuration: configuration,
            tokenProvider: tokenProvider
        )
        self.session = session
    }

    /// Opens an authenticated SSE stream and retries once after a 401 by refreshing tokens.
    /// - Parameter request: Low-level Responses request payload.
    /// - Returns: A stream of provider-facing SSE events.
    public func streamResponse(_ request: OpenAIResponseRequest) -> AsyncThrowingStream<OpenAIResponseStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await streamResponse(
                        request,
                        continuation: continuation
                    )
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

    private func streamResponse(
        _ request: OpenAIResponseRequest,
        continuation: AsyncThrowingStream<OpenAIResponseStreamEvent, Error>.Continuation
    ) async throws {
        let retryPolicy = builder.configuration.transport.retryPolicy
        var tokens = try await builder.tokenProvider.currentTokens()
        var refreshedAfterUnauthorized = false
        var attempt = 1

        while true {
            do {
                let urlRequest = try builder.makeURLRequest(
                    for: request,
                    tokens: tokens,
                    streaming: true
                )
                let (lines, response) = try await session.streamLines(for: urlRequest)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AgentTransportError.invalidResponse(provider: .openAI)
                }

                if httpResponse.statusCode == 401, !refreshedAfterUnauthorized {
                    tokens = try await builder.tokenProvider.refreshTokens(reason: .unauthorized)
                    refreshedAfterUnauthorized = true
                    continue
                }

                if retryPolicy.shouldRetry(afterAttempt: attempt, statusCode: httpResponse.statusCode) {
                    attempt += 1
                    try await sleepForRetryIfNeeded(retryPolicy.backoff)
                    continue
                }

                try await consume(lines: lines, response: response, continuation: continuation)
                return
            } catch let error as AgentAuthError {
                throw error
            } catch let error as AgentProviderError {
                throw error
            } catch let error as AgentTransportError {
                if retryPolicy.shouldRetry(afterAttempt: attempt) {
                    attempt += 1
                    try await sleepForRetryIfNeeded(retryPolicy.backoff)
                    continue
                }
                throw error
            } catch let error as AgentDecodingError {
                throw error
            } catch let error as AgentStreamError {
                throw error
            } catch {
                let mappedError = AgentTransportError.requestFailed(
                    provider: .openAI,
                    description: String(describing: error)
                )
                if retryPolicy.shouldRetry(afterAttempt: attempt) {
                    attempt += 1
                    try await sleepForRetryIfNeeded(retryPolicy.backoff)
                    continue
                }
                throw mappedError
            }
        }
    }

    private func consume(
        lines: AsyncThrowingStream<String, Error>,
        response: URLResponse,
        continuation: AsyncThrowingStream<OpenAIResponseStreamEvent, Error>.Continuation
    ) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentTransportError.invalidResponse(provider: .openAI)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AgentProviderError.unsuccessfulResponse(
                provider: .openAI,
                statusCode: httpResponse.statusCode
            )
        }

        var dataLines: [String] = []
        for try await line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.isEmpty {
                if let event = try decodeAuthenticatedSSEEvent(from: dataLines, provider: .openAI) {
                    continuation.yield(event)
                }
                dataLines.removeAll(keepingCapacity: true)
                continue
            }

            if trimmedLine.hasPrefix("event:") {
                if let event = try decodeAuthenticatedSSEEvent(from: dataLines, provider: .openAI) {
                    continuation.yield(event)
                }
                dataLines.removeAll(keepingCapacity: true)
                continue
            }

            if trimmedLine.hasPrefix("data:") {
                dataLines.append(
                    String(trimmedLine.dropFirst(5))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }

        if let event = try decodeAuthenticatedSSEEvent(from: dataLines, provider: .openAI) {
            continuation.yield(event)
        }
    }
}

private func decodeAuthenticatedSSEEvent(
    from dataLines: [String],
    provider: AgentProviderID
) throws -> OpenAIResponseStreamEvent? {
    guard !dataLines.isEmpty else {
        return nil
    }

    let data = dataLines.joined(separator: "\n")
    guard data != "[DONE]" else {
        return nil
    }

    let jsonData = Data(data.utf8)
    let envelope: OpenAIAuthenticatedStreamEventEnvelope
    do {
        envelope = try JSONDecoder().decode(OpenAIAuthenticatedStreamEventEnvelope.self, from: jsonData)
    } catch {
        throw AgentStreamError.eventDecodingFailed(provider: provider)
    }

    switch envelope.type {
    case "response.created":
        guard let response = envelope.response else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "missing response payload"))
        }
        return .responseCreated(response)
    case "response.output_text.delta":
        return .outputTextDelta(try JSONDecoder().decode(OpenAIResponseTextDeltaEvent.self, from: jsonData))
    case "response.output_item.done":
        return .outputItemDone(try JSONDecoder().decode(OpenAIResponseOutputItemDoneEvent.self, from: jsonData))
    case "response.failed":
        guard let response = envelope.response else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "missing response payload"))
        }
        return .responseFailed(response)
    case "response.incomplete":
        guard let response = envelope.response else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "missing response payload"))
        }
        return .responseIncomplete(response)
    case "error":
        return .error(try JSONDecoder().decode(OpenAIResponseStreamErrorEvent.self, from: jsonData))
    case "response.completed":
        guard let response = envelope.response else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "missing response payload"))
        }
        return .responseCompleted(response)
    default:
        return nil
    }
}

private struct OpenAIAuthenticatedStreamEventEnvelope: Decodable {
    let type: String
    let response: OpenAIResponse?
}

private func sleepForRetryIfNeeded(_ strategy: AgentHTTPBackoffStrategy) async throws {
    guard let delay = strategy.delayDuration() else {
        return
    }
    try await Task.sleep(for: delay)
}
