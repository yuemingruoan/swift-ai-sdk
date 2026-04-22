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
                tools: request.tools?.map(\.toolDescriptor) ?? [],
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

    /// Creates an Anthropic token-usage payload.
    /// - Parameters:
    ///   - inputTokens: Input tokens counted by the provider.
    ///   - outputTokens: Output tokens counted by the provider.
    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
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

/// Provider-neutral representation of an Anthropic tool call.
public struct AnthropicToolCall: Equatable, Sendable {
    public var callID: String
    public var invocation: ToolInvocation

    /// Creates a provider-neutral Anthropic tool-call projection.
    /// - Parameters:
    ///   - callID: Provider-generated tool-call identifier.
    ///   - invocation: Provider-neutral tool invocation payload.
    public init(callID: String, invocation: ToolInvocation) {
        self.callID = callID
        self.invocation = invocation
    }
}

/// Provider-neutral projection of an Anthropic response.
public struct AnthropicResponseProjection: Equatable, Sendable {
    public var messages: [AgentMessage]
    public var toolCalls: [AnthropicToolCall]

    /// Creates a provider-neutral Anthropic response projection.
    /// - Parameters:
    ///   - messages: Provider-neutral output messages projected from the response.
    ///   - toolCalls: Provider-neutral tool calls projected from the response.
    public init(messages: [AgentMessage], toolCalls: [AnthropicToolCall]) {
        self.messages = messages
        self.toolCalls = toolCalls
    }
}

public struct AnthropicProjectionOptions: Equatable, Sendable {
    public var includeThinking: Bool

    /// Creates projection policy for convenience Anthropic abstractions.
    /// Raw provider-facing response types continue to preserve thinking blocks.
    public init(includeThinking: Bool = false) {
        self.includeThinking = includeThinking
    }

    /// Omits thinking blocks when projecting provider output into provider-neutral messages.
    public static let omitThinking = Self(includeThinking: false)

    /// Preserves thinking blocks by tagging them as text during projection.
    public static let preserveThinking = Self(includeThinking: true)
}

public extension AnthropicResponseProjection {
    /// Converts the projection into provider-neutral stream events.
    /// - Returns: Provider-neutral events represented by the projection.
    func agentStreamEvents() -> [AgentStreamEvent] {
        var events = toolCalls.map { toolCall in
            AgentStreamEvent.toolCall(
                AgentToolCall(callID: toolCall.callID, invocation: toolCall.invocation)
            )
        }

        if !messages.isEmpty {
            events.append(.messagesCompleted(messages))
        }

        return events
    }
}

public extension AnthropicMessageResponse {
    /// Projects a raw Anthropic response into provider-neutral messages and tool calls.
    /// - Returns: Provider-neutral messages and tool calls projected from the raw response.
    /// - Throws: An error if the raw response cannot be represented by the provider-neutral model.
    func projectedOutput(
        options: AnthropicProjectionOptions = .init()
    ) throws -> AnthropicResponseProjection {
        guard role == .assistant else {
            throw AnthropicConversionError.unsupportedResponseMessageRole(role.rawValue)
        }

        var parts: [MessagePart] = []
        var toolCalls: [AnthropicToolCall] = []

        for block in content {
            switch block {
            case .text(let text):
                parts.append(.text(text))

            case .toolUse(let toolUse):
                toolCalls.append(
                    AnthropicToolCall(
                        callID: toolUse.id,
                        invocation: ToolInvocation(
                            toolName: toolUse.name,
                            arguments: toolUse.input
                        )
                    )
                )

            case .toolResult:
                throw AnthropicConversionError.unsupportedResponseContentBlock("tool_result")

            case .thinking:
                guard
                    options.includeThinking,
                    let thinkingText = block.projectedThinkingText
                else {
                    continue
                }
                parts.append(.text(thinkingText))
            }
        }

        let messages = parts.isEmpty ? [] : [AgentMessage(role: .assistant, parts: parts)]
        return AnthropicResponseProjection(messages: messages, toolCalls: toolCalls)
    }
}

/// High-level facade for Anthropic Messages APIs and tool-loop orchestration.
public struct AnthropicMessagesClient: Sendable {
    private let transport: any AnthropicMessagesTransport
    private let streamingTransport: (any AnthropicMessagesStreamingTransport)?
    private let defaultProjectionOptions: AnthropicProjectionOptions

    /// Creates a high-level Anthropic Messages client.
    /// - Parameters:
    ///   - transport: Low-level transport used for standard JSON Messages calls.
    ///   - streamingTransport: Optional SSE transport used when streaming is requested.
    public init(
        transport: any AnthropicMessagesTransport,
        streamingTransport: (any AnthropicMessagesStreamingTransport)? = nil,
        projectionOptions: AnthropicProjectionOptions = .omitThinking
    ) {
        self.transport = transport
        self.streamingTransport = streamingTransport
        self.defaultProjectionOptions = projectionOptions
    }

    /// Creates a high-level Anthropic Messages client with a named default projection policy.
    /// - Parameters:
    ///   - transport: Low-level transport used for standard JSON Messages calls.
    ///   - streamingTransport: Optional SSE transport used when streaming is requested.
    ///   - defaultProjectionOptions: Default policy applied by high-level projected helpers.
    public init(
        transport: any AnthropicMessagesTransport,
        streamingTransport: (any AnthropicMessagesStreamingTransport)? = nil,
        defaultProjectionOptions: AnthropicProjectionOptions
    ) {
        self.init(
            transport: transport,
            streamingTransport: streamingTransport,
            projectionOptions: defaultProjectionOptions
        )
    }

    /// Creates a raw Anthropic response from a prebuilt request.
    /// - Parameter request: Prebuilt low-level Anthropic request payload.
    /// - Returns: The decoded raw Anthropic response.
    /// - Throws: An error returned by the underlying transport.
    public func createMessage(_ request: AnthropicMessagesRequest) async throws -> AnthropicMessageResponse {
        try await transport.createMessage(request)
    }

    /// Projects a raw Anthropic response into provider-neutral output.
    /// - Parameter request: Prebuilt low-level Anthropic request payload.
    /// - Parameter options: Optional override for whether the projected convenience shape should preserve thinking blocks.
    /// - Returns: Provider-neutral messages and tool calls projected from the raw response.
    /// - Throws: An error if transport execution or projection fails.
    public func createProjectedResponse(
        _ request: AnthropicMessagesRequest,
        options: AnthropicProjectionOptions? = nil
    ) async throws -> AnthropicResponseProjection {
        try await createMessage(request).projectedOutput(options: resolvedProjectionOptions(options))
    }

    /// Repeatedly resolves tool calls until Anthropic returns a completed response without new tool work.
    /// - Parameters:
    ///   - request: Initial low-level request to send.
    ///   - executor: Tool executor used to satisfy model-issued tool calls.
    ///   - maxIterations: Maximum number of model/tool follow-up loops allowed.
    ///   - projectionOptions: Optional override for whether projected convenience output should preserve thinking blocks.
    /// - Returns: The final provider-neutral projection after tool execution is complete.
    /// - Throws: An error if the tool-call loop exceeds the iteration budget, transport execution fails, or projection fails.
    public func resolveToolCalls(
        _ request: AnthropicMessagesRequest,
        using executor: ToolExecutor,
        maxIterations: Int = 8,
        projectionOptions: AnthropicProjectionOptions? = nil
    ) async throws -> AnthropicResponseProjection {
        var remainingIterations = maxIterations
        var currentRequest = request
        let projectionOptions = resolvedProjectionOptions(projectionOptions)

        while true {
            guard remainingIterations > 0 else {
                throw AgentRuntimeError.toolCallLimitExceeded(provider: .anthropic, maxIterations: maxIterations)
            }

            let response = try await createMessage(currentRequest)
            let projection = try response.projectedOutput(options: projectionOptions)
            guard response.stopReason == .toolUse, !projection.toolCalls.isEmpty else {
                return projection
            }

            let followUpMessage = try await makeToolResultMessage(
                for: projection.toolCalls,
                using: executor
            )
            currentRequest = AnthropicMessagesRequest(
                model: currentRequest.model,
                maxTokens: currentRequest.maxTokens,
                system: currentRequest.system,
                messages: currentRequest.messages + [
                    AnthropicMessage(role: .assistant, content: response.content),
                    followUpMessage,
                ],
                tools: currentRequest.tools?.map(\.toolDescriptor) ?? []
            )
            remainingIterations -= 1
        }
    }

    /// Streams provider-neutral events from Anthropic, with optional tool-loop resolution and projection policy override.
    /// - Parameters:
    ///   - request: Initial low-level request to send.
    ///   - executor: Optional tool executor used when tool calls should be resolved automatically.
    ///   - stream: Whether to prefer the Anthropic SSE transport.
    ///   - maxIterations: Maximum number of model/tool follow-up loops allowed.
    ///   - projectionOptions: Optional override for whether projected convenience output should preserve thinking blocks.
    /// - Returns: A stream of provider-neutral events projected from Anthropic output.
    public func projectedResponseEvents(
        _ request: AnthropicMessagesRequest,
        using executor: ToolExecutor? = nil,
        stream: Bool = false,
        maxIterations: Int = 8,
        projectionOptions: AnthropicProjectionOptions? = nil
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let projectionOptions = resolvedProjectionOptions(projectionOptions)
        if stream, let streamingTransport {
            if let executor {
                return streamResolvedResponse(
                    request,
                    transport: streamingTransport,
                    using: executor,
                    maxIterations: maxIterations,
                    projectionOptions: projectionOptions
                )
            }

            return AnthropicMessagesStreamingClient(
                transport: streamingTransport,
                projectionOptions: projectionOptions
            )
                .streamProjectedResponse(request)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let executor {
                        try await streamResolvedResponse(
                            request,
                            using: executor,
                            maxIterations: maxIterations,
                            projectionOptions: projectionOptions,
                            into: continuation
                        )
                    } else {
                        let projection = try await createProjectedResponse(
                            request,
                            options: projectionOptions
                        )
                        for event in projection.agentStreamEvents() {
                            continuation.yield(event)
                        }
                        continuation.finish()
                    }
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

private extension AnthropicMessagesClient {
    func resolvedProjectionOptions(_ options: AnthropicProjectionOptions?) -> AnthropicProjectionOptions {
        options ?? defaultProjectionOptions
    }

    func streamResolvedResponse(
        _ request: AnthropicMessagesRequest,
        using executor: ToolExecutor,
        maxIterations: Int,
        projectionOptions: AnthropicProjectionOptions,
        into continuation: AsyncThrowingStream<AgentStreamEvent, Error>.Continuation
    ) async throws {
        var remainingIterations = maxIterations
        var currentRequest = request

        while true {
            guard remainingIterations > 0 else {
                throw AgentRuntimeError.toolCallLimitExceeded(provider: .anthropic, maxIterations: maxIterations)
            }

            let response = try await createMessage(currentRequest)
            let projection = try response.projectedOutput(options: projectionOptions)
            for event in projection.agentStreamEvents() {
                continuation.yield(event)
            }

            guard response.stopReason == .toolUse, !projection.toolCalls.isEmpty else {
                continuation.finish()
                return
            }

            let followUpMessage = try await makeToolResultMessage(
                for: projection.toolCalls,
                using: executor
            )
            currentRequest = AnthropicMessagesRequest(
                model: currentRequest.model,
                maxTokens: currentRequest.maxTokens,
                system: currentRequest.system,
                messages: currentRequest.messages + [
                    AnthropicMessage(role: .assistant, content: response.content),
                    followUpMessage,
                ],
                tools: currentRequest.tools?.map(\.toolDescriptor) ?? []
            )
            remainingIterations -= 1
        }
    }

    func streamResolvedResponse(
        _ request: AnthropicMessagesRequest,
        transport: any AnthropicMessagesStreamingTransport,
        using executor: ToolExecutor,
        maxIterations: Int,
        projectionOptions: AnthropicProjectionOptions
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var remainingIterations = maxIterations
                    var currentRequest = request

                    while true {
                        guard remainingIterations > 0 else {
                            throw AgentRuntimeError.toolCallLimitExceeded(provider: .anthropic, maxIterations: maxIterations)
                        }

                        let response = try await streamProjectedResponse(
                            currentRequest,
                            transport: transport,
                            projectionOptions: projectionOptions,
                            into: continuation
                        )
                        let projection = try response.projectedOutput(options: projectionOptions)

                        guard response.stopReason == .toolUse, !projection.toolCalls.isEmpty else {
                            continuation.finish()
                            return
                        }

                        let followUpMessage = try await makeToolResultMessage(
                            for: projection.toolCalls,
                            using: executor
                        )
                        currentRequest = AnthropicMessagesRequest(
                            model: currentRequest.model,
                            maxTokens: currentRequest.maxTokens,
                            system: currentRequest.system,
                            messages: currentRequest.messages + [
                                AnthropicMessage(role: .assistant, content: response.content),
                                followUpMessage,
                            ],
                            tools: currentRequest.tools?.map(\.toolDescriptor) ?? [],
                            stream: true
                        )
                        remainingIterations -= 1
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func streamProjectedResponse(
        _ request: AnthropicMessagesRequest,
        transport: any AnthropicMessagesStreamingTransport,
        projectionOptions: AnthropicProjectionOptions,
        into continuation: AsyncThrowingStream<AgentStreamEvent, Error>.Continuation
    ) async throws -> AnthropicMessageResponse {
        var accumulator = AnthropicStreamingProjectionAccumulator(
            projectionOptions: projectionOptions
        )

        for try await event in transport.streamMessage(request) {
            for projectedEvent in try accumulator.consume(event) {
                continuation.yield(projectedEvent)
            }
        }

        guard let response = try accumulator.finalizedResponse() else {
            throw AgentStreamError.responseFailed(provider: .anthropic, status: "incomplete_stream")
        }

        return response
    }

    func makeToolResultMessage(
        for toolCalls: [AnthropicToolCall],
        using executor: ToolExecutor
    ) async throws -> AnthropicMessage {
        var content: [AnthropicContentBlock] = []
        content.reserveCapacity(toolCalls.count)

        for toolCall in toolCalls {
            let result = try await executor.invoke(toolCall.invocation)
            content.append(
                .toolResult(
                    AnthropicToolResult(
                        toolUseID: toolCall.callID,
                        content: try toolResultContent(from: result),
                        isError: false
                    )
                )
            )
        }

        return AnthropicMessage(role: .user, content: content)
    }

    func toolResultContent(from result: ToolResult) throws -> String {
        switch result.payload {
        case .string(let text):
            return text
        default:
            let data = try JSONEncoder().encode(
                AnthropicToolJSONValue(toolValue: result.payload)
            )
            return String(decoding: data, as: UTF8.self)
        }
    }
}

/// Lower-level helper that converts the Anthropic streaming transport into provider-neutral events.
public struct AnthropicMessagesStreamingClient: Sendable {
    private let transport: any AnthropicMessagesStreamingTransport
    private let defaultProjectionOptions: AnthropicProjectionOptions

    /// Creates a lower-level streaming projection client with a default projection policy.
    public init(
        transport: any AnthropicMessagesStreamingTransport,
        projectionOptions: AnthropicProjectionOptions = .omitThinking
    ) {
        self.transport = transport
        self.defaultProjectionOptions = projectionOptions
    }

    /// Streams provider-neutral events projected from a raw Anthropic SSE stream.
    public func streamProjectedResponse(
        _ request: AnthropicMessagesRequest,
        options: AnthropicProjectionOptions? = nil
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let projectionOptions = options ?? defaultProjectionOptions
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var accumulator = AnthropicStreamingProjectionAccumulator(
                        projectionOptions: projectionOptions
                    )

                    for try await event in transport.streamMessage(request) {
                        for projectedEvent in try accumulator.consume(event) {
                            continuation.yield(projectedEvent)
                        }
                    }

                    _ = try accumulator.finalizedResponse()
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

private struct AnthropicStreamingToolUseState {
    var id: String
    var name: String
    var input: [String: ToolValue]
    var partialJSON: String
}

private struct AnthropicStreamingProjectionAccumulator {
    var projectionOptions: AnthropicProjectionOptions
    var initialMessage: AnthropicMessageResponse?
    var stopReason: AnthropicStopReason?
    var stopSequence: String?
    var usage: AnthropicUsage?
    var textBlocks: [Int: String] = [:]
    var thinkingBlocks: [Int: AnthropicThinkingBlock] = [:]
    var toolUseBlocks: [Int: AnthropicStreamingToolUseState] = [:]
    var completedBlocks: [Int: AnthropicContentBlock] = [:]
    var messageStopped = false

    mutating func consume(_ event: AnthropicMessageStreamEvent) throws -> [AgentStreamEvent] {
        switch event {
        case .messageStart(let event):
            initialMessage = event.message
            usage = event.message.usage
            return []

        case .contentBlockStart(let event):
            switch event.contentBlock.type {
            case "text":
                textBlocks[event.index] = event.contentBlock.text ?? ""
            case "thinking":
                thinkingBlocks[event.index] = .init(
                    thinking: event.contentBlock.thinking,
                    signature: event.contentBlock.signature
                )
            case "tool_use":
                toolUseBlocks[event.index] = .init(
                    id: event.contentBlock.id ?? "",
                    name: event.contentBlock.name ?? "",
                    input: event.contentBlock.input ?? [:],
                    partialJSON: ""
                )
            default:
                break
            }
            return []

        case .contentBlockDelta(let event):
            switch event.delta.type {
            case "text_delta":
                let delta = event.delta.text ?? ""
                textBlocks[event.index, default: ""].append(delta)
                return delta.isEmpty ? [] : [.textDelta(delta)]

            case "input_json_delta":
                toolUseBlocks[event.index]?.partialJSON.append(event.delta.partialJSON ?? "")
                return []

            case "thinking_delta":
                thinkingBlocks[event.index, default: .init()].thinking = (
                    thinkingBlocks[event.index]?.thinking ?? ""
                ) + (event.delta.thinking ?? "")
                return []

            case "signature_delta":
                thinkingBlocks[event.index, default: .init()].signature = (
                    thinkingBlocks[event.index]?.signature ?? ""
                ) + (event.delta.signature ?? "")
                return []

            default:
                return []
            }

        case .contentBlockStop(let event):
            if let text = textBlocks[event.index] {
                completedBlocks[event.index] = .text(text)
            }

            if let thinking = thinkingBlocks.removeValue(forKey: event.index) {
                completedBlocks[event.index] = .thinking(thinking)
            }

            if let toolUse = toolUseBlocks.removeValue(forKey: event.index) {
                let parsedInput = try parseStreamingToolInput(
                    partialJSON: toolUse.partialJSON,
                    fallback: toolUse.input
                )
                let block = AnthropicToolUse(
                    id: toolUse.id,
                    name: toolUse.name,
                    input: parsedInput
                )
                completedBlocks[event.index] = .toolUse(block)
                return [
                    .toolCall(
                        .init(
                            callID: block.id,
                            invocation: .init(
                                toolName: block.name,
                                arguments: block.input
                            )
                        )
                    ),
                ]
            }

            return []

        case .messageDelta(let event):
            stopReason = event.delta.stopReason
            stopSequence = event.delta.stopSequence
            let currentUsage = usage ?? .init(inputTokens: 0, outputTokens: 0)
            usage = .init(
                inputTokens: event.usage?.inputTokens ?? currentUsage.inputTokens,
                outputTokens: event.usage?.outputTokens ?? currentUsage.outputTokens
            )
            return []

        case .messageStop:
            messageStopped = true
            guard let response = try finalizedResponse() else {
                return []
            }
            let projection = try response.projectedOutput(options: projectionOptions)
            return projection.messages.isEmpty ? [] : [.messagesCompleted(projection.messages)]

        case .ping, .unknown:
            return []

        case .error(let error):
            throw AgentStreamError.serverError(
                provider: .anthropic,
                type: error.error.type,
                code: nil,
                message: error.error.message
            )
        }
    }

    func finalizedResponse() throws -> AnthropicMessageResponse? {
        guard let initialMessage, messageStopped else {
            return nil
        }

        let content = completedBlocks
            .sorted { $0.key < $1.key }
            .map(\.value)

        return AnthropicMessageResponse(
            id: initialMessage.id,
            model: initialMessage.model,
            role: initialMessage.role,
            content: content,
            stopReason: stopReason ?? initialMessage.stopReason,
            stopSequence: stopSequence ?? initialMessage.stopSequence,
            usage: usage ?? initialMessage.usage
        )
    }
}

private extension AnthropicContentBlock {
    var projectedThinkingText: String? {
        guard case .thinking(let thinking) = self else {
            return nil
        }
        guard
            let text = thinking.thinking?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return nil
        }
        return "<thinking>\(text)</thinking>"
    }
}

private func parseStreamingToolInput(
    partialJSON: String,
    fallback: [String: ToolValue]
) throws -> [String: ToolValue] {
    guard !partialJSON.isEmpty else {
        return fallback
    }

    guard let data = partialJSON.data(using: .utf8) else {
        throw AgentStreamError.eventDecodingFailed(provider: .anthropic)
    }

    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw AgentStreamError.eventDecodingFailed(provider: .anthropic)
    }

    guard let dictionary = object as? [String: Any] else {
        throw AgentStreamError.eventDecodingFailed(provider: .anthropic)
    }

    return try dictionary.mapValues(convertStreamingToolValue)
}

private func convertStreamingToolValue(_ value: Any) throws -> ToolValue {
    switch value {
    case let string as String:
        return .string(string)
    case let bool as Bool:
        return .boolean(bool)
    case let int as Int:
        return .integer(int)
    case let number as NSNumber:
        return CFNumberIsFloatType(number) ? .number(number.doubleValue) : .integer(number.intValue)
    case let array as [Any]:
        return .array(try array.map(convertStreamingToolValue))
    case let dictionary as [String: Any]:
        return .object(try dictionary.mapValues(convertStreamingToolValue))
    case _ as NSNull:
        return .null
    default:
        throw AgentStreamError.eventDecodingFailed(provider: .anthropic)
    }
}

private extension AnthropicTool {
    var toolDescriptor: ToolDescriptor {
        ToolDescriptor.remote(
            name: name,
            transport: "",
            inputSchema: inputSchema.toolInputSchema,
            description: description
        )
    }
}

private extension AnthropicToolSchema {
    var toolInputSchema: ToolInputSchema {
        switch self {
        case .string:
            return .string
        case .integer:
            return .integer
        case .number:
            return .number
        case .boolean:
            return .boolean
        case .array(let items):
            return .array(items: items.toolInputSchema)
        case .object(let properties, let required):
            return .object(
                properties: properties.mapValues(\.toolInputSchema),
                required: required
            )
        }
    }
}

private indirect enum AnthropicToolJSONValue {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case array([AnthropicToolJSONValue])
    case object([String: AnthropicToolJSONValue])
    case null

    init(toolValue: ToolValue) {
        switch toolValue {
        case .string(let string):
            self = .string(string)
        case .integer(let integer):
            self = .integer(integer)
        case .number(let number):
            self = .number(number)
        case .boolean(let boolean):
            self = .boolean(boolean)
        case .array(let array):
            self = .array(array.map(AnthropicToolJSONValue.init(toolValue:)))
        case .object(let object):
            self = .object(object.mapValues(AnthropicToolJSONValue.init(toolValue:)))
        case .null:
            self = .null
        }
    }
}

extension AnthropicToolJSONValue: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        if let boolean = try? container.decode(Bool.self) {
            self = .boolean(boolean)
            return
        }
        if let integer = try? container.decode(Int.self) {
            self = .integer(integer)
            return
        }
        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }
        if let array = try? container.decode([AnthropicToolJSONValue].self) {
            self = .array(array)
            return
        }
        if let object = try? container.decode([String: AnthropicToolJSONValue].self) {
            self = .object(object)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "unsupported tool JSON value"
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .integer(let integer):
            try container.encode(integer)
        case .number(let number):
            try container.encode(number)
        case .boolean(let boolean):
            try container.encode(boolean)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        case .null:
            try container.encodeNil()
        }
    }
}
