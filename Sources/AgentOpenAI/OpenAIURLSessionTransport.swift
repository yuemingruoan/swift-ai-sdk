import AgentCore
import Foundation

/// Connection settings for direct OpenAI Responses HTTP transports.
public struct OpenAIAPIConfiguration: Equatable, Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var userAgent: String?
    public var transport: AgentHTTPTransportConfiguration

    /// Creates configuration for direct OpenAI Responses transports.
    /// - Parameters:
    ///   - apiKey: Bearer token used for `Authorization`.
    ///   - baseURL: Base API URL, defaulting to the official OpenAI v1 endpoint.
    ///   - userAgent: Optional `User-Agent` header override.
    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        transport: AgentHTTPTransportConfiguration = .init(),
        userAgent: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transport = transport
        self.userAgent = userAgent
    }
}

/// Errors thrown by the direct OpenAI HTTP and SSE transports.
public enum OpenAITransportError: Error, Equatable, Sendable {
    case invalidResponse
    case unsuccessfulStatusCode(Int)
    case streamingResponseFailed(OpenAIResponseStatus)
    case streamingServerError(type: String, code: String?, message: String?)
}

/// Minimal async HTTP session used by non-streaming OpenAI transports.
public protocol OpenAIHTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: OpenAIHTTPSession {}

/// Minimal async line-streaming session used by SSE transports.
public protocol OpenAIHTTPLineStreamingSession: Sendable {
    func streamLines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse)
}

extension URLSession: OpenAIHTTPLineStreamingSession {
    public func streamLines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse) {
        let (bytes, response) = try await bytes(for: request)
        return (
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await line in bytes.lines {
                            continuation.yield(line)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            },
            response
        )
    }
}

/// Lower-level builder that converts ``OpenAIResponseRequest`` into `URLRequest`.
public struct OpenAIResponsesRequestBuilder: Sendable {
    public let configuration: OpenAIAPIConfiguration

    /// Creates a request builder with a transport configuration.
    /// - Parameter configuration: HTTP settings used when generating `URLRequest` values.
    public init(configuration: OpenAIAPIConfiguration) {
        self.configuration = configuration
    }

    /// Builds a standard JSON Responses request.
    /// - Parameter request: Low-level Responses request payload.
    /// - Returns: A configured `URLRequest` ready for JSON execution.
    /// - Throws: An error if the request body cannot be encoded.
    public func makeURLRequest(for request: OpenAIResponseRequest) throws -> URLRequest {
        let endpoint = configuration.baseURL.appendingPathComponent("responses")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
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

    /// Builds a streaming Responses request with `stream = true`.
    /// - Parameter request: Base low-level Responses request payload.
    /// - Returns: A configured `URLRequest` ready for SSE execution.
    /// - Throws: An error if the request body cannot be encoded.
    public func makeStreamingURLRequest(for request: OpenAIResponseRequest) throws -> URLRequest {
        try makeURLRequest(
            for: OpenAIResponseRequest(
                model: request.model,
                input: request.input,
                instructions: request.instructions,
                previousResponseID: request.previousResponseID,
                store: request.store,
                promptCacheKey: request.promptCacheKey,
                stream: true,
                tools: request.tools,
                toolChoice: request.toolChoice
            )
        )
    }
}

/// Concrete `URLSession` transport for non-streaming OpenAI Responses calls.
public struct URLSessionOpenAIResponsesTransport: OpenAIResponsesTransport, Sendable {
    private let builder: OpenAIResponsesRequestBuilder
    private let session: any OpenAIHTTPSession

    /// Creates a `URLSession`-backed non-streaming Responses transport.
    /// - Parameters:
    ///   - configuration: HTTP settings used when generating requests.
    ///   - session: Injectable HTTP session for transport customization or testing.
    public init(
        configuration: OpenAIAPIConfiguration,
        session: any OpenAIHTTPSession = URLSession.shared
    ) {
        self.builder = OpenAIResponsesRequestBuilder(configuration: configuration)
        self.session = session
    }

    /// Sends a request and decodes the JSON response body.
    /// - Parameter request: Low-level Responses request payload.
    /// - Returns: The decoded raw Responses payload.
    /// - Throws: An error if request encoding, network execution, or response decoding fails.
    public func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse {
        let retryPolicy = builder.configuration.transport.retryPolicy

        for attempt in 1...retryPolicy.maxAttempts {
            do {
                let urlRequest = try builder.makeURLRequest(for: request)
                let (data, response) = try await session.data(for: urlRequest)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AgentTransportError.invalidResponse(provider: .openAI)
                }
                if retryPolicy.shouldRetry(afterAttempt: attempt, statusCode: httpResponse.statusCode) {
                    try await sleepForRetryIfNeeded(retryPolicy.backoff)
                    continue
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
                    provider: .openAI,
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
            provider: .openAI,
            description: "request exhausted retry policy"
        )
    }
}

/// Transport contract for OpenAI Responses SSE streams.
public protocol OpenAIResponsesStreamingTransport: Sendable {
    func streamResponse(_ request: OpenAIResponseRequest) -> AsyncThrowingStream<OpenAIResponseStreamEvent, Error>
}

/// Incremental text delta emitted by the OpenAI Responses streaming API.
public struct OpenAIResponseTextDeltaEvent: Codable, Equatable, Sendable {
    public var itemID: String
    public var outputIndex: Int
    public var contentIndex: Int
    public var delta: String
    public var sequenceNumber: Int

    /// Creates a streaming text-delta event payload.
    /// - Parameters:
    ///   - itemID: Identifier of the output item emitting the delta.
    ///   - outputIndex: Output index associated with the item.
    ///   - contentIndex: Content index associated with the delta.
    ///   - delta: Incremental text fragment.
    ///   - sequenceNumber: Provider sequence number for event ordering.
    public init(
        itemID: String,
        outputIndex: Int,
        contentIndex: Int,
        delta: String,
        sequenceNumber: Int
    ) {
        self.itemID = itemID
        self.outputIndex = outputIndex
        self.contentIndex = contentIndex
        self.delta = delta
        self.sequenceNumber = sequenceNumber
    }

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case delta
        case sequenceNumber = "sequence_number"
    }
}

/// Completed output item emitted by the OpenAI Responses streaming API.
public struct OpenAIResponseOutputItemDoneEvent: Codable, Equatable, Sendable {
    public var item: OpenAIResponseOutputItem
    public var outputIndex: Int
    public var sequenceNumber: Int

    /// Creates a completed output-item event payload.
    /// - Parameters:
    ///   - item: Completed output item emitted by the provider.
    ///   - outputIndex: Output index associated with the item.
    ///   - sequenceNumber: Provider sequence number for event ordering.
    public init(
        item: OpenAIResponseOutputItem,
        outputIndex: Int,
        sequenceNumber: Int
    ) {
        self.item = item
        self.outputIndex = outputIndex
        self.sequenceNumber = sequenceNumber
    }

    enum CodingKeys: String, CodingKey {
        case item
        case outputIndex = "output_index"
        case sequenceNumber = "sequence_number"
    }
}

/// Provider-facing SSE event model emitted by OpenAI Responses streaming.
public enum OpenAIResponseStreamEvent: Equatable, Sendable {
    case responseCreated(OpenAIResponse)
    case outputTextDelta(OpenAIResponseTextDeltaEvent)
    case outputItemDone(OpenAIResponseOutputItemDoneEvent)
    case responseFailed(OpenAIResponse)
    case responseIncomplete(OpenAIResponse)
    case error(OpenAIResponseStreamErrorEvent)
    case responseCompleted(OpenAIResponse)
}

public extension OpenAIResponseStreamEvent {
    /// Projects a transport event into one or more provider-neutral stream events.
    /// - Returns: Provider-neutral events represented by the transport event.
    /// - Throws: An error if the event represents a failed or invalid provider response.
    func projectedAgentStreamEvents() throws -> [AgentStreamEvent] {
        switch self {
        case .responseCreated:
            return []
        case .outputTextDelta(let delta):
            return [.textDelta(delta.delta)]
        case .outputItemDone:
            return []
        case .responseFailed(let response):
            throw AgentStreamError.responseFailed(provider: .openAI, status: response.status.rawValue)
        case .responseIncomplete(let response):
            throw AgentStreamError.responseFailed(provider: .openAI, status: response.status.rawValue)
        case .error(let error):
            throw AgentStreamError.serverError(
                provider: .openAI,
                type: error.type,
                code: error.code,
                message: error.message
            )
        case .responseCompleted(let response):
            return try response.projectedOutput().agentStreamEvents()
        }
    }
}

/// Error event emitted by the OpenAI Responses streaming API.
public struct OpenAIResponseStreamErrorEvent: Codable, Equatable, Sendable {
    public var type: String
    public var code: String?
    public var message: String?

    /// Creates a streaming error event payload.
    /// - Parameters:
    ///   - type: Provider error type.
    ///   - code: Optional provider-specific error code.
    ///   - message: Optional human-readable error description.
    public init(type: String, code: String? = nil, message: String? = nil) {
        self.type = type
        self.code = code
        self.message = message
    }
}

/// Concrete `URLSession` transport for OpenAI Responses SSE streams.
public struct URLSessionOpenAIResponsesStreamingTransport: OpenAIResponsesStreamingTransport, Sendable {
    private let builder: OpenAIResponsesRequestBuilder
    private let session: any OpenAIHTTPLineStreamingSession

    /// Creates a `URLSession`-backed Responses SSE transport.
    /// - Parameters:
    ///   - configuration: HTTP settings used when generating requests.
    ///   - session: Injectable line-streaming session for transport customization or testing.
    public init(
        configuration: OpenAIAPIConfiguration,
        session: any OpenAIHTTPLineStreamingSession = URLSession.shared
    ) {
        self.builder = OpenAIResponsesRequestBuilder(configuration: configuration)
        self.session = session
    }

    /// Opens an SSE stream and decodes provider-facing stream events.
    /// - Parameter request: Low-level Responses request payload.
    /// - Returns: A stream of provider-facing SSE events.
    public func streamResponse(_ request: OpenAIResponseRequest) -> AsyncThrowingStream<OpenAIResponseStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try builder.makeStreamingURLRequest(for: request)
                    let (lines, response) = try await session.streamLines(for: urlRequest)
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
                            if let event = try decodeSSEEvent(
                                from: dataLines,
                                provider: .openAI
                            ) {
                                continuation.yield(event)
                            }
                            dataLines.removeAll(keepingCapacity: true)
                            continue
                        }

                        if trimmedLine.hasPrefix("event:") {
                            if let event = try decodeSSEEvent(
                                from: dataLines,
                                provider: .openAI
                            ) {
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

                    if let event = try decodeSSEEvent(from: dataLines, provider: .openAI) {
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

private struct OpenAIStreamEventEnvelope: Decodable {
    let type: String
    let response: OpenAIResponse?
}

private func decodeSSEEvent(
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
    let envelope: OpenAIStreamEventEnvelope
    do {
        envelope = try JSONDecoder().decode(OpenAIStreamEventEnvelope.self, from: jsonData)
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

private func sleepForRetryIfNeeded(_ strategy: AgentHTTPBackoffStrategy) async throws {
    guard let delay = strategy.delayDuration() else {
        return
    }
    try await Task.sleep(for: delay)
}
