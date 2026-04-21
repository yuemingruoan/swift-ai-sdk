import AgentCore
import Foundation

public struct AnthropicAPIConfiguration: Equatable, Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var version: String

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        version: String = "2023-06-01"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.version = version
    }
}

public enum AnthropicTransportError: Error, Equatable, Sendable {
    case invalidResponse
    case unsuccessfulStatusCode(Int)
}

public protocol AnthropicHTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: AnthropicHTTPSession {}

public protocol AnthropicMessagesTransport: Sendable {
    func createMessage(_ request: AnthropicMessagesRequest) async throws -> AnthropicMessageResponse
}

public struct AnthropicMessagesRequestBuilder: Sendable {
    public let configuration: AnthropicAPIConfiguration

    public init(configuration: AnthropicAPIConfiguration) {
        self.configuration = configuration
    }

    public func makeURLRequest(for request: AnthropicMessagesRequest) throws -> URLRequest {
        let endpoint = configuration.baseURL.appendingPathComponent("messages")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(configuration.version, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        return urlRequest
    }
}

public struct URLSessionAnthropicMessagesTransport: AnthropicMessagesTransport, Sendable {
    private let builder: AnthropicMessagesRequestBuilder
    private let session: any AnthropicHTTPSession

    public init(
        configuration: AnthropicAPIConfiguration,
        session: any AnthropicHTTPSession = URLSession.shared
    ) {
        self.builder = AnthropicMessagesRequestBuilder(configuration: configuration)
        self.session = session
    }

    public func createMessage(_ request: AnthropicMessagesRequest) async throws -> AnthropicMessageResponse {
        let urlRequest = try builder.makeURLRequest(for: request)
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicTransportError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AnthropicTransportError.unsuccessfulStatusCode(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
    }
}

public enum AnthropicMessagesClientError: Error, Equatable, Sendable {
    case toolCallLimitExceeded(Int)
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

public struct AnthropicUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

public struct AnthropicMessageResponse: Codable, Equatable, Sendable {
    public var id: String
    public var model: String
    public var role: AnthropicMessageRole
    public var content: [AnthropicContentBlock]
    public var stopReason: AnthropicStopReason?
    public var stopSequence: String?
    public var usage: AnthropicUsage

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
}

public struct AnthropicToolCall: Equatable, Sendable {
    public var callID: String
    public var invocation: ToolInvocation

    public init(callID: String, invocation: ToolInvocation) {
        self.callID = callID
        self.invocation = invocation
    }
}

public struct AnthropicResponseProjection: Equatable, Sendable {
    public var messages: [AgentMessage]
    public var toolCalls: [AnthropicToolCall]

    public init(messages: [AgentMessage], toolCalls: [AnthropicToolCall]) {
        self.messages = messages
        self.toolCalls = toolCalls
    }
}

public extension AnthropicResponseProjection {
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
    func projectedOutput() throws -> AnthropicResponseProjection {
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
            }
        }

        let messages = parts.isEmpty ? [] : [AgentMessage(role: .assistant, parts: parts)]
        return AnthropicResponseProjection(messages: messages, toolCalls: toolCalls)
    }
}

public struct AnthropicMessagesClient: Sendable {
    private let transport: any AnthropicMessagesTransport

    public init(transport: any AnthropicMessagesTransport) {
        self.transport = transport
    }

    public func createMessage(_ request: AnthropicMessagesRequest) async throws -> AnthropicMessageResponse {
        try await transport.createMessage(request)
    }

    public func createProjectedResponse(
        _ request: AnthropicMessagesRequest
    ) async throws -> AnthropicResponseProjection {
        try await createMessage(request).projectedOutput()
    }

    public func resolveToolCalls(
        _ request: AnthropicMessagesRequest,
        using executor: ToolExecutor,
        maxIterations: Int = 8
    ) async throws -> AnthropicResponseProjection {
        var remainingIterations = maxIterations
        var currentRequest = request

        while true {
            guard remainingIterations > 0 else {
                throw AnthropicMessagesClientError.toolCallLimitExceeded(maxIterations)
            }

            let response = try await createMessage(currentRequest)
            let projection = try response.projectedOutput()
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

    public func projectedResponseEvents(
        _ request: AnthropicMessagesRequest,
        using executor: ToolExecutor? = nil,
        maxIterations: Int = 8
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let executor {
                        try await streamResolvedResponse(
                            request,
                            using: executor,
                            maxIterations: maxIterations,
                            into: continuation
                        )
                    } else {
                        let projection = try await createProjectedResponse(request)
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
    func streamResolvedResponse(
        _ request: AnthropicMessagesRequest,
        using executor: ToolExecutor,
        maxIterations: Int,
        into continuation: AsyncThrowingStream<AgentStreamEvent, Error>.Continuation
    ) async throws {
        var remainingIterations = maxIterations
        var currentRequest = request

        while true {
            guard remainingIterations > 0 else {
                throw AnthropicMessagesClientError.toolCallLimitExceeded(maxIterations)
            }

            let response = try await createMessage(currentRequest)
            let projection = try response.projectedOutput()
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
