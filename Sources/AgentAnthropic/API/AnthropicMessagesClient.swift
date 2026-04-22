import AgentCore
import Foundation

/// Connection settings for direct Anthropic Messages HTTP transports.
public struct AnthropicAPIConfiguration: Equatable, Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var version: String
    public var userAgent: String?
    public var transport: AgentHTTPTransportConfiguration

    /// Creates configuration for direct Anthropic Messages transports.
    /// - Parameters:
    ///   - apiKey: API key sent as `x-api-key`.
    ///   - baseURL: Base API URL, defaulting to the official Anthropic v1 endpoint.
    ///   - version: Anthropic API version header value.
    ///   - userAgent: Optional `User-Agent` header override.
    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        version: String = "2023-06-01",
        transport: AgentHTTPTransportConfiguration = .init(),
        userAgent: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.version = version
        self.transport = transport
        self.userAgent = userAgent
    }
}

/// Minimal async HTTP session used by Anthropic transports.
public protocol AnthropicHTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: AnthropicHTTPSession {}

/// Minimal transport contract for Anthropic Messages requests.
public protocol AnthropicMessagesTransport: Sendable {
    func createMessage(_ request: AnthropicMessagesRequest) async throws -> AnthropicMessageResponse
}

/// Lower-level builder that converts ``AnthropicMessagesRequest`` into `URLRequest`.
public struct AnthropicMessagesRequestBuilder: Sendable {
    public let configuration: AnthropicAPIConfiguration

    /// Creates a request builder with transport configuration.
    /// - Parameter configuration: HTTP settings used when generating `URLRequest` values.
    public init(configuration: AnthropicAPIConfiguration) {
        self.configuration = configuration
    }

    /// Builds a JSON Messages request.
    /// - Parameter request: Low-level Anthropic request payload.
    /// - Returns: A configured `URLRequest` ready for execution.
    /// - Throws: An error if the request body cannot be encoded.
    public func makeURLRequest(for request: AnthropicMessagesRequest) throws -> URLRequest {
        let endpoint = configuration.baseURL.appendingPathComponent("messages")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(configuration.version, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let timeoutInterval = configuration.transport.timeoutInterval {
            urlRequest.timeoutInterval = timeoutInterval
        }
        if let userAgent = configuration.transport.userAgent ?? configuration.userAgent, !userAgent.isEmpty {
            urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        if let requestID = configuration.transport.requestID, !requestID.isEmpty {
            urlRequest.setValue(requestID, forHTTPHeaderField: "X-Request-Id")
        }
        for (header, value) in configuration.transport.additionalHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }
        urlRequest.httpBody = try JSONEncoder().encode(request)
        return urlRequest
    }

    /// Builds a streaming Messages request with `stream = true`.
    /// - Parameter request: Base low-level Messages request payload.
    /// - Returns: A configured `URLRequest` ready for SSE execution.
    /// - Throws: An error if the request body cannot be encoded.
    public func makeStreamingURLRequest(for request: AnthropicMessagesRequest) throws -> URLRequest {
        try makeURLRequest(
            for: AnthropicMessagesRequest(
                model: request.model,
                maxTokens: request.maxTokens,
                system: request.system,
                messages: request.messages,
                tools: request.tools ?? [],
                stream: true
            )
        )
    }
}

/// Concrete `URLSession` transport for Anthropic Messages requests.
public struct URLSessionAnthropicMessagesTransport: AnthropicMessagesTransport, Sendable {
    private let builder: AnthropicMessagesRequestBuilder
    private let session: any AnthropicHTTPSession

    /// Creates a `URLSession`-backed Anthropic Messages transport.
    /// - Parameters:
    ///   - configuration: HTTP settings used when generating requests.
    ///   - session: Injectable HTTP session for transport customization or testing.
    public init(
        configuration: AnthropicAPIConfiguration,
        session: any AnthropicHTTPSession = URLSession.shared
    ) {
        self.builder = AnthropicMessagesRequestBuilder(configuration: configuration)
        self.session = session
    }

    /// Sends a request and decodes the Anthropic message response.
    /// - Parameter request: Low-level Anthropic request payload.
    /// - Returns: The decoded raw Anthropic response.
    /// - Throws: An error if request encoding, network execution, or response decoding fails.
    public func createMessage(_ request: AnthropicMessagesRequest) async throws -> AnthropicMessageResponse {
        let retryPolicy = builder.configuration.transport.retryPolicy

        for attempt in 1...retryPolicy.maxAttempts {
            do {
                let urlRequest = try builder.makeURLRequest(for: request)
                let (data, response) = try await session.data(for: urlRequest)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AgentTransportError.invalidResponse(provider: .anthropic)
                }
                if retryPolicy.shouldRetry(afterAttempt: attempt, statusCode: httpResponse.statusCode) {
                    try await sleepForRetryIfNeeded(retryPolicy.backoff)
                    continue
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw AgentProviderError.unsuccessfulResponse(
                        provider: .anthropic,
                        statusCode: httpResponse.statusCode
                    )
                }

                do {
                    return try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
                } catch {
                    throw AgentDecodingError.responseBody(
                        provider: .anthropic,
                        description: String(describing: error)
                    )
                }
            } catch let error as AgentProviderError {
                throw error
            } catch let error as AgentTransportError {
                if retryPolicy.shouldRetry(afterAttempt: attempt) {
                    try await sleepForRetryIfNeeded(retryPolicy.backoff)
                    continue
                }
                throw error
            } catch let error as AgentDecodingError {
                throw error
            } catch {
                let mappedError = AgentTransportError.requestFailed(
                    provider: .anthropic,
                    description: String(describing: error)
                )
                if retryPolicy.shouldRetry(afterAttempt: attempt) {
                    try await sleepForRetryIfNeeded(retryPolicy.backoff)
                    continue
                }
                throw mappedError
            }
        }

        throw AgentTransportError.requestFailed(
            provider: .anthropic,
            description: "request exhausted retry policy"
        )
    }
}

private func sleepForRetryIfNeeded(_ strategy: AgentHTTPBackoffStrategy) async throws {
    guard let delay = strategy.delayDuration() else {
        return
    }
    try await Task.sleep(for: delay)
}

public enum AnthropicStopReason: String, Codable, Equatable, Sendable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
    case toolUse = "tool_use"
    case pauseTurn = "pause_turn"
    case refusal
    case modelContextWindowExceeded = "model_context_window_exceeded"
}

private func decodeAnthropicStopReasonIfPresent(
    from container: KeyedDecodingContainer<AnthropicMessageResponse.CodingKeys>,
    forKey key: AnthropicMessageResponse.CodingKeys
) throws -> AnthropicStopReason? {
    let rawValue = try container.decodeIfPresent(String.self, forKey: key)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let rawValue, !rawValue.isEmpty else {
        return nil
    }
    return AnthropicStopReason(rawValue: rawValue)
}

public struct AnthropicUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var serverToolUse: AnthropicServerToolUsage?

    /// Creates an Anthropic token-usage payload.
    /// - Parameters:
    ///   - inputTokens: Input tokens counted by the provider.
    ///   - outputTokens: Output tokens counted by the provider.
    public init(
        inputTokens: Int,
        outputTokens: Int,
        serverToolUse: AnthropicServerToolUsage? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.serverToolUse = serverToolUse
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case serverToolUse = "server_tool_use"
    }
}

public struct AnthropicServerToolUsage: Codable, Equatable, Sendable {
    public var webSearchRequests: Int?

    public init(webSearchRequests: Int? = nil) {
        self.webSearchRequests = webSearchRequests
    }

    enum CodingKeys: String, CodingKey {
        case webSearchRequests = "web_search_requests"
    }
}

/// Raw response payload returned by the Anthropic Messages API.
public struct AnthropicMessageResponse: Codable, Equatable, Sendable {
    public var id: String
    public var model: String
    public var role: AnthropicMessageRole
    public var content: [AnthropicContentBlock]
    public var stopReason: AnthropicStopReason?
    public var stopSequence: String?
    public var usage: AnthropicUsage

    /// Creates a raw Anthropic response payload.
    /// - Parameters:
    ///   - id: Provider response identifier.
    ///   - model: Model identifier that produced the response.
    ///   - role: Provider role associated with the response.
    ///   - content: Raw content blocks returned by the provider.
    ///   - stopReason: Optional provider stop reason.
    ///   - stopSequence: Optional provider stop sequence.
    ///   - usage: Token usage reported by the provider.
    public init(
        id: String,
        model: String,
        role: AnthropicMessageRole,
        content: [AnthropicContentBlock],
        stopReason: AnthropicStopReason?,
        stopSequence: String?,
        usage: AnthropicUsage
    ) {
        self.id = id
        self.model = model
        self.role = role
        self.content = content
        self.stopReason = stopReason
        self.stopSequence = stopSequence
        self.usage = usage
    }

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case role
        case content
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        model = try container.decode(String.self, forKey: .model)
        role = try container.decode(AnthropicMessageRole.self, forKey: .role)
        content = try container.decode([AnthropicContentBlock].self, forKey: .content)
        stopReason = try decodeAnthropicStopReasonIfPresent(from: container, forKey: .stopReason)
        stopSequence = try container.decodeIfPresent(String.self, forKey: .stopSequence)
        usage = try container.decode(AnthropicUsage.self, forKey: .usage)
    }
}
