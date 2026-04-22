import AgentCore
import Foundation

/// Minimal async line-streaming session used by Anthropic SSE transports.
public protocol AnthropicHTTPLineStreamingSession: Sendable {
    func streamLines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse)
}

extension URLSession: AnthropicHTTPLineStreamingSession {
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

/// Transport contract for Anthropic Messages SSE streams.
public protocol AnthropicMessagesStreamingTransport: Sendable {
    /// Streams provider-facing raw SSE events for a Messages request.
    func streamMessage(_ request: AnthropicMessagesRequest) -> AsyncThrowingStream<AnthropicMessageStreamEvent, Error>
}

/// Content block payload emitted by Anthropic message streams.
public struct AnthropicMessageStreamContentBlock: Codable, Equatable, Sendable {
    public var type: String
    public var text: String?
    public var id: String?
    public var name: String?
    public var input: [String: ToolValue]?
    public var thinking: String?
    public var signature: String?

    /// Creates a provider-facing stream content block payload.
    public init(
        type: String,
        text: String? = nil,
        id: String? = nil,
        name: String? = nil,
        input: [String: ToolValue]? = nil,
        thinking: String? = nil,
        signature: String? = nil
    ) {
        self.type = type
        self.text = text
        self.id = id
        self.name = name
        self.input = input
        self.thinking = thinking
        self.signature = signature
    }
}

/// Delta payload emitted by Anthropic message streams.
public struct AnthropicMessageStreamDeltaPayload: Codable, Equatable, Sendable {
    public var type: String
    public var text: String?
    public var partialJSON: String?
    public var thinking: String?
    public var signature: String?

    /// Creates a provider-facing stream delta payload.
    public init(
        type: String,
        text: String? = nil,
        partialJSON: String? = nil,
        thinking: String? = nil,
        signature: String? = nil
    ) {
        self.type = type
        self.text = text
        self.partialJSON = partialJSON
        self.thinking = thinking
        self.signature = signature
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case partialJSON = "partial_json"
        case thinking
        case signature
    }
}

/// Provider-facing stream event emitted when the SSE stream starts a message.
public struct AnthropicMessageStartEvent: Codable, Equatable, Sendable {
    public var message: AnthropicMessageResponse

    /// Creates a stream event for message start.
    public init(message: AnthropicMessageResponse) {
        self.message = message
    }
}

/// Provider-facing stream event emitted when a content block starts.
public struct AnthropicContentBlockStartEvent: Codable, Equatable, Sendable {
    public var index: Int
    public var contentBlock: AnthropicMessageStreamContentBlock

    /// Creates a stream event for content-block start.
    public init(index: Int, contentBlock: AnthropicMessageStreamContentBlock) {
        self.index = index
        self.contentBlock = contentBlock
    }

    enum CodingKeys: String, CodingKey {
        case index
        case contentBlock = "content_block"
    }
}

/// Provider-facing stream event emitted for content-block deltas.
public struct AnthropicContentBlockDeltaEvent: Codable, Equatable, Sendable {
    public var index: Int
    public var delta: AnthropicMessageStreamDeltaPayload

    /// Creates a stream event for content-block delta.
    public init(index: Int, delta: AnthropicMessageStreamDeltaPayload) {
        self.index = index
        self.delta = delta
    }
}

/// Provider-facing stream event emitted when a content block completes.
public struct AnthropicContentBlockStopEvent: Codable, Equatable, Sendable {
    public var index: Int

    /// Creates a stream event for content-block completion.
    public init(index: Int) {
        self.index = index
    }
}

/// Provider-facing delta payload emitted for message-level updates.
public struct AnthropicMessageDeltaPayload: Codable, Equatable, Sendable {
    public var stopReason: AnthropicStopReason?
    public var stopSequence: String?

    /// Creates a message-level stream delta payload.
    public init(
        stopReason: AnthropicStopReason?,
        stopSequence: String?
    ) {
        self.stopReason = stopReason
        self.stopSequence = stopSequence
    }

    enum CodingKeys: String, CodingKey {
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
    }

    /// Decodes message delta payloads while treating empty stop reasons as absent.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawStopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawStopReason, !rawStopReason.isEmpty {
            stopReason = AnthropicStopReason(rawValue: rawStopReason)
        } else {
            stopReason = nil
        }
        stopSequence = try container.decodeIfPresent(String.self, forKey: .stopSequence)
    }
}

/// Provider-facing usage update emitted during Anthropic message streaming.
public struct AnthropicMessageDeltaUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int?
    public var outputTokens: Int?

    /// Creates a usage update emitted during streaming.
    public init(inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

/// Provider-facing stream event emitted for message-level deltas.
public struct AnthropicMessageDeltaEvent: Codable, Equatable, Sendable {
    public var delta: AnthropicMessageDeltaPayload
    public var usage: AnthropicMessageDeltaUsage?

    /// Creates a stream event for message-level deltas.
    public init(
        delta: AnthropicMessageDeltaPayload,
        usage: AnthropicMessageDeltaUsage? = nil
    ) {
        self.delta = delta
        self.usage = usage
    }
}

/// Provider-facing stream server-error payload.
public struct AnthropicStreamErrorPayload: Codable, Equatable, Sendable {
    public var type: String
    public var message: String?

    /// Creates a provider-facing stream error payload.
    public init(type: String, message: String? = nil) {
        self.type = type
        self.message = message
    }
}

/// Provider-facing stream event emitted when Anthropic returns an error event.
public struct AnthropicStreamErrorEvent: Codable, Equatable, Sendable {
    public var error: AnthropicStreamErrorPayload

    /// Creates a provider-facing stream error event.
    public init(error: AnthropicStreamErrorPayload) {
        self.error = error
    }
}

/// Provider-facing raw SSE event model emitted by Anthropic Messages streaming.
public enum AnthropicMessageStreamEvent: Equatable, Sendable {
    case messageStart(AnthropicMessageStartEvent)
    case contentBlockStart(AnthropicContentBlockStartEvent)
    case contentBlockDelta(AnthropicContentBlockDeltaEvent)
    case contentBlockStop(AnthropicContentBlockStopEvent)
    case messageDelta(AnthropicMessageDeltaEvent)
    case messageStop
    case ping
    case error(AnthropicStreamErrorEvent)
    case unknown(type: String, rawData: String)
}

/// Concrete `URLSession` transport for Anthropic Messages SSE streams.
public struct URLSessionAnthropicMessagesStreamingTransport: AnthropicMessagesStreamingTransport, Sendable {
    private let builder: AnthropicMessagesRequestBuilder
    private let session: any AnthropicHTTPLineStreamingSession

    /// Creates a `URLSession`-backed Anthropic SSE transport.
    public init(
        configuration: AnthropicAPIConfiguration,
        session: any AnthropicHTTPLineStreamingSession = URLSession.shared
    ) {
        self.builder = AnthropicMessagesRequestBuilder(configuration: configuration)
        self.session = session
    }

    /// Executes a streaming Messages request and yields raw Anthropic SSE events.
    public func streamMessage(_ request: AnthropicMessagesRequest) -> AsyncThrowingStream<AnthropicMessageStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try builder.makeStreamingURLRequest(for: request)
                    let (lines, response) = try await session.streamLines(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AgentTransportError.invalidResponse(provider: .anthropic)
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw AgentProviderError.unsuccessfulResponse(
                            provider: .anthropic,
                            statusCode: httpResponse.statusCode
                        )
                    }

                    var dataLines: [String] = []
                    for try await line in lines {
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

                        if trimmedLine.isEmpty {
                            if let event = try decodeAnthropicSSEEvent(from: dataLines) {
                                continuation.yield(event)
                            }
                            dataLines.removeAll(keepingCapacity: true)
                            continue
                        }

                        if trimmedLine.hasPrefix("event:") {
                            if let event = try decodeAnthropicSSEEvent(from: dataLines) {
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

                    if let event = try decodeAnthropicSSEEvent(from: dataLines) {
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

private struct AnthropicStreamEventEnvelope: Decodable {
    let type: String
}

private func decodeAnthropicSSEEvent(
    from dataLines: [String]
) throws -> AnthropicMessageStreamEvent? {
    guard !dataLines.isEmpty else {
        return nil
    }

    let data = dataLines.joined(separator: "\n")
    guard data != "[DONE]" else {
        return nil
    }

    let jsonData = Data(data.utf8)
    let envelope: AnthropicStreamEventEnvelope
    do {
        envelope = try JSONDecoder().decode(AnthropicStreamEventEnvelope.self, from: jsonData)
    } catch {
        throw AgentStreamError.eventDecodingFailed(provider: .anthropic)
    }

    do {
        switch envelope.type {
        case "message_start":
            return .messageStart(try JSONDecoder().decode(AnthropicMessageStartEvent.self, from: jsonData))
        case "content_block_start":
            return .contentBlockStart(try JSONDecoder().decode(AnthropicContentBlockStartEvent.self, from: jsonData))
        case "content_block_delta":
            return .contentBlockDelta(try JSONDecoder().decode(AnthropicContentBlockDeltaEvent.self, from: jsonData))
        case "content_block_stop":
            return .contentBlockStop(try JSONDecoder().decode(AnthropicContentBlockStopEvent.self, from: jsonData))
        case "message_delta":
            return .messageDelta(try JSONDecoder().decode(AnthropicMessageDeltaEvent.self, from: jsonData))
        case "message_stop":
            return .messageStop
        case "ping":
            return .ping
        case "error":
            return .error(try JSONDecoder().decode(AnthropicStreamErrorEvent.self, from: jsonData))
        default:
            return .unknown(type: envelope.type, rawData: data)
        }
    } catch {
        throw AgentStreamError.eventDecodingFailed(provider: .anthropic)
    }
}
