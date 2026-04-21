import AgentCore
import Foundation

/// Minimal transport contract for non-streaming OpenAI Responses requests.
public protocol OpenAIResponsesTransport: Sendable {
    func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse
}

/// Follow-up strategy used after a model response emits tool calls.
public enum OpenAIResponsesFollowUpStrategy: Equatable, Sendable {
    case previousResponseID
    case replayInput
}

/// High-level facade for OpenAI Responses APIs and tool-loop orchestration.
public struct OpenAIResponsesClient: Sendable {
    private let transport: any OpenAIResponsesTransport
    private let streamingTransport: (any OpenAIResponsesStreamingTransport)?
    private let followUpStrategy: OpenAIResponsesFollowUpStrategy

    /// Creates a high-level Responses client.
    /// - Parameters:
    ///   - transport: Non-streaming transport used for standard JSON Responses calls.
    ///   - streamingTransport: Optional SSE transport used when streaming is requested.
    ///   - followUpStrategy: Strategy used to construct follow-up requests after tool calls.
    public init(
        transport: any OpenAIResponsesTransport,
        streamingTransport: (any OpenAIResponsesStreamingTransport)? = nil,
        followUpStrategy: OpenAIResponsesFollowUpStrategy = .previousResponseID
    ) {
        self.transport = transport
        self.streamingTransport = streamingTransport
        self.followUpStrategy = followUpStrategy
    }

    /// Creates a raw OpenAI response from provider-neutral messages.
    /// - Parameters:
    ///   - model: Model identifier sent to the Responses API.
    ///   - messages: Provider-neutral input messages for the request.
    ///   - previousResponseID: Optional previous response identifier used for follow-up requests.
    /// - Returns: The decoded raw Responses payload.
    /// - Throws: An error if request construction or transport execution fails.
    public func createResponse(
        model: String,
        messages: [AgentMessage],
        previousResponseID: String? = nil
    ) async throws -> OpenAIResponse {
        try await transport.createResponse(
            OpenAIResponseRequest(
                model: model,
                messages: messages,
                previousResponseID: previousResponseID
            )
        )
    }

    /// Creates a raw OpenAI response from a fully prepared request model.
    /// - Parameter request: Prebuilt low-level request payload.
    /// - Returns: The decoded raw Responses payload.
    /// - Throws: An error returned by the underlying transport.
    public func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse {
        try await transport.createResponse(request)
    }

    /// Returns the provider-neutral projection for a message-based request.
    /// - Parameters:
    ///   - model: Model identifier sent to the Responses API.
    ///   - messages: Provider-neutral input messages for the request.
    ///   - previousResponseID: Optional previous response identifier used for follow-up requests.
    /// - Returns: Provider-neutral messages and tool calls projected from the raw response.
    /// - Throws: An error if request construction, transport execution, or projection fails.
    public func createProjectedResponse(
        model: String,
        messages: [AgentMessage],
        previousResponseID: String? = nil
    ) async throws -> OpenAIResponseProjection {
        let response = try await createResponse(
            model: model,
            messages: messages,
            previousResponseID: previousResponseID
        )
        return try response.projectedOutput()
    }

    /// Returns the provider-neutral projection for a prebuilt request.
    /// - Parameter request: Prebuilt low-level request payload.
    /// - Returns: Provider-neutral messages and tool calls projected from the raw response.
    /// - Throws: An error if transport execution or projection fails.
    public func createProjectedResponse(
        _ request: OpenAIResponseRequest
    ) async throws -> OpenAIResponseProjection {
        let response = try await createResponse(request)
        return try response.projectedOutput()
    }

    /// Repeatedly resolves tool calls until the model returns a completed response without new tool work.
    /// - Parameters:
    ///   - request: Initial low-level request to send.
    ///   - executor: Tool executor used to satisfy model-issued tool calls.
    ///   - maxIterations: Maximum number of model/tool follow-up loops allowed.
    /// - Returns: The final provider-neutral projection after tool execution is complete.
    /// - Throws: An error if the tool-call loop exceeds the iteration budget, transport execution fails, or projection fails.
    public func resolveToolCalls(
        _ request: OpenAIResponseRequest,
        using executor: ToolExecutor,
        maxIterations: Int = 8
    ) async throws -> OpenAIResponseProjection {
        var remainingIterations = maxIterations
        var currentRequest = request

        while true {
            guard remainingIterations > 0 else {
                throw AgentRuntimeError.toolCallLimitExceeded(provider: .openAI, maxIterations: maxIterations)
            }

            let response = try await createResponse(currentRequest)
            let projection = try response.projectedOutput()
            guard !projection.toolCalls.isEmpty else {
                return projection
            }

            currentRequest = try await followUpRequest(
                from: currentRequest,
                response: response,
                toolCalls: projection.toolCalls,
                using: executor
            )
            remainingIterations -= 1
        }
    }

    public func resolveToolCalls(
        model: String,
        messages: [AgentMessage],
        tools: [ToolDescriptor],
        using executor: ToolExecutor,
        previousResponseID: String? = nil,
        maxIterations: Int = 8
    ) async throws -> OpenAIResponseProjection {
        try await resolveToolCalls(
            OpenAIResponseRequest(
                model: model,
                messages: messages,
                previousResponseID: previousResponseID,
                tools: tools
            ),
            using: executor,
            maxIterations: maxIterations
        )
    }

    /// Streams provider-neutral events for a request, with optional SSE streaming.
    /// - Parameters:
    ///   - request: Prebuilt low-level request to send.
    ///   - stream: Whether to prefer the configured streaming transport over one-shot execution.
    /// - Returns: A provider-neutral event stream for the request lifecycle.
    public func projectedResponseEvents(
        _ request: OpenAIResponseRequest,
        stream: Bool = false
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        if stream, let streamingTransport {
            return OpenAIResponsesStreamingClient(transport: streamingTransport)
                .streamProjectedResponse(request)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let projection = try await createProjectedResponse(request)
                    for event in projection.agentStreamEvents() {
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

    /// Streams provider-neutral events while resolving tool calls automatically.
    /// - Parameters:
    ///   - request: Prebuilt low-level request to send.
    ///   - executor: Tool executor used to satisfy model-issued tool calls.
    ///   - stream: Whether to prefer the configured streaming transport over one-shot execution.
    ///   - maxIterations: Maximum number of model/tool follow-up loops allowed.
    /// - Returns: A provider-neutral event stream that includes tool-call resolution output.
    public func projectedResponseEvents(
        _ request: OpenAIResponseRequest,
        using executor: ToolExecutor,
        stream: Bool = false,
        maxIterations: Int = 8
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        if stream, let streamingTransport {
            return streamResolvedResponse(
                request,
                transport: streamingTransport,
                using: executor,
                maxIterations: maxIterations
            )
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let projection = try await resolveToolCalls(
                        request,
                        using: executor,
                        maxIterations: maxIterations
                    )
                    for event in projection.agentStreamEvents() {
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

    /// Convenience overload that builds an ``OpenAIResponseRequest`` from provider-neutral messages.
    /// - Parameters:
    ///   - model: Model identifier sent to the Responses API.
    ///   - messages: Provider-neutral input messages for the request.
    ///   - previousResponseID: Optional previous response identifier used for follow-up requests.
    ///   - stream: Whether to prefer the configured streaming transport over one-shot execution.
    /// - Returns: A provider-neutral event stream for the request lifecycle.
    /// - Throws: An error if the request cannot be constructed from the supplied messages.
    public func projectedResponseEvents(
        model: String,
        messages: [AgentMessage],
        previousResponseID: String? = nil,
        stream: Bool = false
    ) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        projectedResponseEvents(
            try OpenAIResponseRequest(
                model: model,
                messages: messages,
                previousResponseID: previousResponseID
            ),
            stream: stream
        )
    }

    /// Convenience overload that builds a tool-enabled request from provider-neutral messages.
    /// - Parameters:
    ///   - model: Model identifier sent to the Responses API.
    ///   - messages: Provider-neutral input messages for the request.
    ///   - tools: Tool descriptors to expose to the model.
    ///   - executor: Tool executor used to satisfy model-issued tool calls.
    ///   - previousResponseID: Optional previous response identifier used for follow-up requests.
    ///   - stream: Whether to prefer the configured streaming transport over one-shot execution.
    ///   - maxIterations: Maximum number of model/tool follow-up loops allowed.
    /// - Returns: A provider-neutral event stream that includes tool-call resolution output.
    /// - Throws: An error if the request cannot be constructed from the supplied messages and tools.
    public func projectedResponseEvents(
        model: String,
        messages: [AgentMessage],
        tools: [ToolDescriptor],
        using executor: ToolExecutor,
        previousResponseID: String? = nil,
        stream: Bool = false,
        maxIterations: Int = 8
    ) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        projectedResponseEvents(
            try OpenAIResponseRequest(
                model: model,
                messages: messages,
                previousResponseID: previousResponseID,
                tools: tools
            ),
            using: executor,
            stream: stream,
            maxIterations: maxIterations
        )
    }
}

/// Lower-level helper that converts the streaming transport into provider-neutral events.
public struct OpenAIResponsesStreamingClient: Sendable {
    private let transport: any OpenAIResponsesStreamingTransport

    /// Creates a streaming helper around a lower-level SSE transport.
    /// - Parameter transport: Transport used to open the Responses SSE stream.
    public init(transport: any OpenAIResponsesStreamingTransport) {
        self.transport = transport
    }

    /// Streams a projected response directly from a streaming transport.
    /// - Parameter request: Prebuilt low-level request payload.
    /// - Returns: A provider-neutral event stream projected from SSE events.
    public func streamProjectedResponse(
        _ request: OpenAIResponseRequest
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var completedOutputItems: [Int: OpenAIResponseOutputItem] = [:]

                    for try await event in transport.streamResponse(request) {
                        switch event {
                        case .outputItemDone(let done):
                            completedOutputItems[done.outputIndex] = done.item

                        case .responseCompleted(let response):
                            let effectiveResponse = withFallbackOutput(
                                response,
                                fallbackItemsByIndex: completedOutputItems
                            )
                            completedOutputItems.removeAll()
                            for projectedEvent in try OpenAIResponseStreamEvent
                                .responseCompleted(effectiveResponse)
                                .projectedAgentStreamEvents() {
                                continuation.yield(projectedEvent)
                            }

                        default:
                            for projectedEvent in try event.projectedAgentStreamEvents() {
                                continuation.yield(projectedEvent)
                            }
                        }
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

    public func streamProjectedResponse(
        model: String,
        messages: [AgentMessage],
        previousResponseID: String? = nil
    ) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        streamProjectedResponse(
            try OpenAIResponseRequest(
                model: model,
                messages: messages,
                previousResponseID: previousResponseID
            )
        )
    }
}

private extension OpenAIResponsesClient {
    func streamResolvedResponse(
        _ request: OpenAIResponseRequest,
        transport: any OpenAIResponsesStreamingTransport,
        using executor: ToolExecutor,
        maxIterations: Int
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var remainingIterations = maxIterations
                    var currentRequest = request

                    while true {
                        guard remainingIterations > 0 else {
                            throw AgentRuntimeError.toolCallLimitExceeded(provider: .openAI, maxIterations: maxIterations)
                        }

                        var nextRequest: OpenAIResponseRequest?
                        var didComplete = false
                        var completedOutputItems: [Int: OpenAIResponseOutputItem] = [:]

                        for try await event in transport.streamResponse(currentRequest) {
                            switch event {
                            case .responseCreated:
                                continue

                            case .outputTextDelta(let delta):
                                continuation.yield(.textDelta(delta.delta))

                            case .outputItemDone(let done):
                                completedOutputItems[done.outputIndex] = done.item

                            case .responseFailed(let response):
                                throw AgentStreamError.responseFailed(
                                    provider: .openAI,
                                    status: response.status.rawValue
                                )

                            case .responseIncomplete(let response):
                                throw AgentStreamError.responseFailed(
                                    provider: .openAI,
                                    status: response.status.rawValue
                                )

                            case .error(let error):
                                throw AgentStreamError.serverError(
                                    provider: .openAI,
                                    type: error.type,
                                    code: error.code,
                                    message: error.message
                                )

                            case .responseCompleted(let response):
                                let effectiveResponse = withFallbackOutput(
                                    response,
                                    fallbackItemsByIndex: completedOutputItems
                                )
                                let projection = try effectiveResponse.projectedOutput()
                                for projectedEvent in projection.agentStreamEvents() {
                                    continuation.yield(projectedEvent)
                                }

                                if projection.toolCalls.isEmpty {
                                    didComplete = true
                                } else {
                                    nextRequest = try await followUpRequest(
                                        from: currentRequest,
                                        response: effectiveResponse,
                                        toolCalls: projection.toolCalls,
                                        using: executor
                                    )
                                }
                            }
                        }

                        if didComplete {
                            continuation.finish()
                            return
                        }

                        guard let nextRequest else {
                            continuation.finish()
                            return
                        }

                        currentRequest = nextRequest
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

    func makeFunctionCallOutputs(
        for toolCalls: [OpenAIResponseToolCall],
        using executor: ToolExecutor
    ) async throws -> [OpenAIResponseInputItem] {
        var items: [OpenAIResponseInputItem] = []
        items.reserveCapacity(toolCalls.count)

        for toolCall in toolCalls {
            let result = try await executor.invoke(toolCall.invocation)
            items.append(
                .functionCallOutput(
                    .init(
                        callID: toolCall.callID,
                        output: try functionCallOutputValue(from: result)
                    )
                )
            )
        }

        return items
    }

    func followUpRequest(
        from request: OpenAIResponseRequest,
        response: OpenAIResponse,
        toolCalls: [OpenAIResponseToolCall],
        using executor: ToolExecutor
    ) async throws -> OpenAIResponseRequest {
        let followUpItems = try await makeFunctionCallOutputs(for: toolCalls, using: executor)
        switch followUpStrategy {
        case .previousResponseID:
            return OpenAIResponseRequest(
                model: request.model,
                input: followUpItems,
                instructions: request.instructions,
                previousResponseID: response.id,
                store: request.store,
                promptCacheKey: request.promptCacheKey,
                stream: request.stream,
                tools: request.tools,
                toolChoice: nil
            )

        case .replayInput:
            return OpenAIResponseRequest(
                model: request.model,
                input: request.input + replayedInputItems(from: response.output) + followUpItems,
                instructions: request.instructions,
                store: request.store,
                promptCacheKey: request.promptCacheKey,
                stream: request.stream,
                tools: request.tools,
                toolChoice: nil
            )
        }
    }

    func functionCallOutputValue(from result: ToolResult) throws -> OpenAIFunctionCallOutputValue {
        switch result.payload {
        case .string(let text):
            return .text(text)
        default:
            let data = try JSONEncoder().encode(OpenAIToolJSONValue(toolValue: result.payload))
            return .text(String(decoding: data, as: UTF8.self))
        }
    }
}

private func replayedInputItems(from output: [OpenAIResponseOutputItem]) -> [OpenAIResponseInputItem] {
    output.map { item in
        switch item {
        case .message(let message):
            .message(
                OpenAIInputMessage(
                    role: message.role,
                    content: message.content.map { content in
                        switch content {
                        case .outputText(let text):
                            .outputText(text)
                        case .refusal(let refusal):
                            .refusal(refusal)
                        }
                    }
                )
            )
        case .functionCall(let functionCall):
            .functionCall(
                OpenAIResponseFunctionCall(
                    callID: functionCall.callID,
                    name: functionCall.name,
                    arguments: functionCall.arguments
                )
            )
        }
    }
}

private func withFallbackOutput(
    _ response: OpenAIResponse,
    fallbackItemsByIndex: [Int: OpenAIResponseOutputItem]
) -> OpenAIResponse {
    guard response.output.isEmpty, !fallbackItemsByIndex.isEmpty else {
        return response
    }

    let output = fallbackItemsByIndex
        .sorted { $0.key < $1.key }
        .map(\.value)

    return OpenAIResponse(
        id: response.id,
        status: response.status,
        output: output
    )
}

private indirect enum OpenAIToolJSONValue {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case array([OpenAIToolJSONValue])
    case object([String: OpenAIToolJSONValue])
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
            self = .array(array.map(OpenAIToolJSONValue.init(toolValue:)))
        case .object(let object):
            self = .object(object.mapValues(OpenAIToolJSONValue.init(toolValue:)))
        case .null:
            self = .null
        }
    }
}

extension OpenAIToolJSONValue: Codable {
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
        if let array = try? container.decode([OpenAIToolJSONValue].self) {
            self = .array(array)
            return
        }
        if let object = try? container.decode([String: OpenAIToolJSONValue].self) {
            self = .object(object)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "unsupported tool JSON value")
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
