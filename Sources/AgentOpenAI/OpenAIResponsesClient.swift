import AgentCore
import Foundation

public protocol OpenAIResponsesTransport: Sendable {
    func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse
}

public enum OpenAIResponsesClientError: Error, Equatable, Sendable {
    case toolCallLimitExceeded(Int)
}

public struct OpenAIResponsesClient: Sendable {
    private let transport: any OpenAIResponsesTransport
    private let streamingTransport: (any OpenAIResponsesStreamingTransport)?

    public init(
        transport: any OpenAIResponsesTransport,
        streamingTransport: (any OpenAIResponsesStreamingTransport)? = nil
    ) {
        self.transport = transport
        self.streamingTransport = streamingTransport
    }

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

    public func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse {
        try await transport.createResponse(request)
    }

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

    public func createProjectedResponse(
        _ request: OpenAIResponseRequest
    ) async throws -> OpenAIResponseProjection {
        let response = try await createResponse(request)
        return try response.projectedOutput()
    }

    public func resolveToolCalls(
        _ request: OpenAIResponseRequest,
        using executor: ToolExecutor,
        maxIterations: Int = 8
    ) async throws -> OpenAIResponseProjection {
        var remainingIterations = maxIterations
        var currentRequest = request

        while true {
            guard remainingIterations > 0 else {
                throw OpenAIResponsesClientError.toolCallLimitExceeded(maxIterations)
            }

            let response = try await createResponse(currentRequest)
            let projection = try response.projectedOutput()
            guard !projection.toolCalls.isEmpty else {
                return projection
            }

            let followUpItems = try await makeFunctionCallOutputs(
                for: projection.toolCalls,
                using: executor
            )
            currentRequest = OpenAIResponseRequest(
                model: currentRequest.model,
                input: followUpItems,
                previousResponseID: response.id,
                stream: currentRequest.stream,
                tools: currentRequest.tools,
                toolChoice: nil
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
}

public struct OpenAIResponsesStreamingClient: Sendable {
    private let transport: any OpenAIResponsesStreamingTransport

    public init(transport: any OpenAIResponsesStreamingTransport) {
        self.transport = transport
    }

    public func streamProjectedResponse(
        _ request: OpenAIResponseRequest
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in transport.streamResponse(request) {
                        for projectedEvent in try event.projectedAgentStreamEvents() {
                            continuation.yield(projectedEvent)
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
