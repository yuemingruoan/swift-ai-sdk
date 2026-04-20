import AgentCore
import Foundation

public indirect enum OpenAIRealtimeValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case array([OpenAIRealtimeValue])
    case object([String: OpenAIRealtimeValue])
    case null
}

extension OpenAIRealtimeValue: Codable {
    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
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
            if let array = try? container.decode([OpenAIRealtimeValue].self) {
                self = .array(array)
                return
            }
            if let object = try? container.decode([String: OpenAIRealtimeValue].self) {
                self = .object(object)
                return
            }
        }

        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "unsupported realtime JSON value")
        )
    }

    public func encode(to encoder: any Encoder) throws {
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

public struct OpenAIRealtimeEvent: Codable, Equatable, Sendable {
    public var type: String
    public var payload: [String: OpenAIRealtimeValue]

    public init(type: String, payload: [String: OpenAIRealtimeValue] = [:]) {
        self.type = type
        self.payload = payload
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard case let .object(object) = try container.decode(OpenAIRealtimeValue.self) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "realtime event must be an object")
        }
        guard case let .string(type)? = object["type"] else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "realtime event missing type")
        }

        var payload = object
        payload.removeValue(forKey: "type")
        self.type = type
        self.payload = payload
    }

    public func encode(to encoder: any Encoder) throws {
        var object = payload
        object["type"] = .string(type)
        var container = encoder.singleValueContainer()
        try container.encode(OpenAIRealtimeValue.object(object))
    }
}

public struct OpenAIRealtimeSession: Codable, Equatable, Sendable {
    public var instructions: String?
    public var tools: [OpenAIResponseTool]?
    public var toolChoice: OpenAIResponseToolChoice?

    public init(
        instructions: String? = nil,
        tools: [ToolDescriptor] = [],
        toolChoice: OpenAIResponseToolChoice? = nil
    ) {
        self.instructions = instructions
        self.tools = tools.isEmpty ? nil : tools.map(OpenAIResponseTool.init(descriptor:))
        self.toolChoice = toolChoice
    }

    enum CodingKeys: String, CodingKey {
        case instructions
        case tools
        case toolChoice = "tool_choice"
    }
}

public struct OpenAIRealtimeSessionUpdateEvent: Codable, Equatable, Sendable {
    public var type: String
    public var session: OpenAIRealtimeSession

    public init(session: OpenAIRealtimeSession) {
        self.type = "session.update"
        self.session = session
    }
}

public struct OpenAIRealtimeInputTextContent: Codable, Equatable, Sendable {
    public var type: String
    public var text: String

    public init(text: String) {
        self.type = "input_text"
        self.text = text
    }
}

public struct OpenAIRealtimeConversationItem: Codable, Equatable, Sendable {
    public var type: String
    public var role: String
    public var content: [OpenAIRealtimeInputTextContent]

    public init(role: String, content: [OpenAIRealtimeInputTextContent]) {
        self.type = "message"
        self.role = role
        self.content = content
    }
}

public struct OpenAIRealtimeFunctionCallOutputItem: Codable, Equatable, Sendable {
    public var type: String
    public var callID: String
    public var output: String

    public init(callID: String, output: String) {
        self.type = "function_call_output"
        self.callID = callID
        self.output = output
    }

    enum CodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
        case output
    }
}

public struct OpenAIRealtimeConversationItemCreateEvent: Codable, Equatable, Sendable {
    public var type: String
    public var item: OpenAIRealtimeConversationItemPayload

    public init(item: OpenAIRealtimeConversationItemPayload) {
        self.type = "conversation.item.create"
        self.item = item
    }

    public static func userText(_ text: String) -> Self {
        Self(
            item: .message(
                OpenAIRealtimeConversationItem(
                    role: "user",
                    content: [.init(text: text)]
                )
            )
        )
    }

    public static func functionCallOutput(callID: String, output: String) -> Self {
        Self(
            item: .functionCallOutput(
                OpenAIRealtimeFunctionCallOutputItem(
                    callID: callID,
                    output: output
                )
            )
        )
    }
}

public enum OpenAIRealtimeConversationItemPayload: Equatable, Sendable {
    case message(OpenAIRealtimeConversationItem)
    case functionCallOutput(OpenAIRealtimeFunctionCallOutputItem)
}

extension OpenAIRealtimeConversationItemPayload: Codable {
    enum CodingKeys: String, CodingKey {
        case type
    }

    enum Kind: String, Codable {
        case message
        case functionCallOutput = "function_call_output"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .message:
            self = .message(try OpenAIRealtimeConversationItem(from: decoder))
        case .functionCallOutput:
            self = .functionCallOutput(try OpenAIRealtimeFunctionCallOutputItem(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .message(let item):
            try item.encode(to: encoder)
        case .functionCallOutput(let item):
            try item.encode(to: encoder)
        }
    }
}

public struct OpenAIRealtimeResponseConfiguration: Codable, Equatable, Sendable {
    public var tools: [OpenAIResponseTool]?
    public var toolChoice: OpenAIResponseToolChoice?

    public init(
        tools: [ToolDescriptor] = [],
        toolChoice: OpenAIResponseToolChoice? = nil
    ) {
        self.tools = tools.isEmpty ? nil : tools.map(OpenAIResponseTool.init(descriptor:))
        self.toolChoice = toolChoice
    }

    enum CodingKeys: String, CodingKey {
        case tools
        case toolChoice = "tool_choice"
    }
}

public struct OpenAIRealtimeResponseCreateEvent: Codable, Equatable, Sendable {
    public var type: String
    public var response: OpenAIRealtimeResponseConfiguration?

    public init(response: OpenAIRealtimeResponseConfiguration? = nil) {
        self.type = "response.create"
        self.response = response
    }
}

public struct OpenAIRealtimeConfiguration: Equatable, Sendable {
    public var apiKey: String
    public var model: String
    public var baseURL: URL

    public init(
        apiKey: String,
        model: String,
        baseURL: URL = URL(string: "wss://api.openai.com/v1/realtime")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }
}

public enum OpenAIRealtimeError: Error, Equatable, Sendable {
    case notConnected
}

public struct OpenAIRealtimeRequestBuilder: Sendable {
    public let configuration: OpenAIRealtimeConfiguration

    public init(configuration: OpenAIRealtimeConfiguration) {
        self.configuration = configuration
    }

    public func makeURLRequest() throws -> URLRequest {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "model", value: configuration.model)]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}

public protocol OpenAIWebSocketConnection: Sendable {
    func connect() async
    func send(text: String) async throws
    func receiveText() async throws -> String
    func cancel() async
}

public protocol OpenAIWebSocketSession: Sendable {
    func makeConnection(with request: URLRequest) -> any OpenAIWebSocketConnection
}

public actor OpenAIRealtimeWebSocketConnection: OpenAIWebSocketConnection {
    private let task: URLSessionWebSocketTask

    public init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    public func connect() async {
        task.resume()
    }

    public func send(text: String) async throws {
        try await task.send(.string(text))
    }

    public func receiveText() async throws -> String {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            return String(decoding: data, as: UTF8.self)
        @unknown default:
            return ""
        }
    }

    public func cancel() async {
        task.cancel()
    }
}

extension URLSession: OpenAIWebSocketSession {
    public func makeConnection(with request: URLRequest) -> any OpenAIWebSocketConnection {
        OpenAIRealtimeWebSocketConnection(task: webSocketTask(with: request))
    }
}

public actor OpenAIRealtimeWebSocketClient {
    private let builder: OpenAIRealtimeRequestBuilder
    private let session: any OpenAIWebSocketSession
    private var connection: (any OpenAIWebSocketConnection)?

    public init(
        configuration: OpenAIRealtimeConfiguration,
        session: any OpenAIWebSocketSession = URLSession.shared
    ) {
        self.builder = OpenAIRealtimeRequestBuilder(configuration: configuration)
        self.session = session
    }

    public func connect() async throws {
        let request = try builder.makeURLRequest()
        let connection = session.makeConnection(with: request)
        self.connection = connection
        await connection.connect()
    }

    public func send(_ event: OpenAIRealtimeEvent) async throws {
        guard let connection else {
            throw OpenAIRealtimeError.notConnected
        }

        let text = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        try await connection.send(text: text)
    }

    public func receive() async throws -> OpenAIRealtimeEvent {
        guard let connection else {
            throw OpenAIRealtimeError.notConnected
        }

        let text = try await connection.receiveText()
        return try JSONDecoder().decode(OpenAIRealtimeEvent.self, from: Data(text.utf8))
    }

    public func receiveProjectedEvents() async throws -> [AgentStreamEvent] {
        try await receive().projectedAgentStreamEvents()
    }

    public func updateSession(instructions: String) async throws {
        let data = try JSONEncoder().encode(
            OpenAIRealtimeSessionUpdateEvent(
                session: .init(instructions: instructions)
            )
        )
        try await send(try JSONDecoder().decode(OpenAIRealtimeEvent.self, from: data))
    }

    public func sendUserText(_ text: String) async throws {
        let data = try JSONEncoder().encode(OpenAIRealtimeConversationItemCreateEvent.userText(text))
        try await send(try JSONDecoder().decode(OpenAIRealtimeEvent.self, from: data))
    }

    public func sendFunctionCallOutput(callID: String, output: String) async throws {
        let data = try JSONEncoder().encode(
            OpenAIRealtimeConversationItemCreateEvent.functionCallOutput(
                callID: callID,
                output: output
            )
        )
        try await send(try JSONDecoder().decode(OpenAIRealtimeEvent.self, from: data))
    }

    public func createResponse() async throws {
        let data = try JSONEncoder().encode(OpenAIRealtimeResponseCreateEvent())
        try await send(try JSONDecoder().decode(OpenAIRealtimeEvent.self, from: data))
    }

    public func receiveUntilTurnFinished(
        using executor: ToolExecutor,
        maxIterations: Int = 8
    ) async throws -> [AgentStreamEvent] {
        var events: [AgentStreamEvent] = []
        var remainingIterations = maxIterations

        while true {
            guard remainingIterations > 0 else {
                throw OpenAIResponsesClientError.toolCallLimitExceeded(maxIterations)
            }

            let realtimeEvent = try await receive()
            switch realtimeEvent.type {
            case "response.output_text.delta":
                let projected = try realtimeEvent.projectedAgentStreamEvents()
                events.append(contentsOf: projected)

            case "response.completed", "response.done":
                let response = try decodeCompletedResponse(from: realtimeEvent)
                let projection = try response.projectedOutput()
                let projected = projection.agentStreamEvents()
                events.append(contentsOf: projected)

                if projection.toolCalls.isEmpty {
                    return events
                }

                for toolCall in projection.toolCalls {
                    let result = try await executor.invoke(toolCall.invocation)
                    try await sendFunctionCallOutput(
                        callID: toolCall.callID,
                        output: try encodeToolResult(result)
                    )
                }
                try await createResponse()
                remainingIterations -= 1

            default:
                continue
            }
        }
    }

    public func disconnect() async {
        await connection?.cancel()
        connection = nil
    }
}

public extension OpenAIRealtimeEvent {
    func projectedAgentStreamEvents() throws -> [AgentStreamEvent] {
        switch type {
        case "response.output_text.delta":
            guard case let .string(delta)? = payload["delta"] else {
                return []
            }
            return [.textDelta(delta)]

        case "response.completed", "response.done":
            guard let responseValue = payload["response"] else {
                return []
            }
            let data = try JSONEncoder().encode(responseValue)
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            return try response.projectedOutput().agentStreamEvents()

        default:
            return []
        }
    }
}

private extension OpenAIRealtimeWebSocketClient {
    func decodeCompletedResponse(from event: OpenAIRealtimeEvent) throws -> OpenAIResponse {
        guard let responseValue = event.payload["response"] else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "missing response payload")
            )
        }
        let data = try JSONEncoder().encode(responseValue)
        return try JSONDecoder().decode(OpenAIResponse.self, from: data)
    }

    func encodeToolResult(_ result: ToolResult) throws -> String {
        switch result.payload {
        case .string(let text):
            return text
        default:
            let data = try JSONEncoder().encode(OpenAIRealtimeToolJSONValue(toolValue: result.payload))
            return String(decoding: data, as: UTF8.self)
        }
    }
}

private indirect enum OpenAIRealtimeToolJSONValue {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case array([OpenAIRealtimeToolJSONValue])
    case object([String: OpenAIRealtimeToolJSONValue])
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
            self = .array(array.map(OpenAIRealtimeToolJSONValue.init(toolValue:)))
        case .object(let object):
            self = .object(object.mapValues(OpenAIRealtimeToolJSONValue.init(toolValue:)))
        case .null:
            self = .null
        }
    }
}

extension OpenAIRealtimeToolJSONValue: Codable {
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
        if let array = try? container.decode([OpenAIRealtimeToolJSONValue].self) {
            self = .array(array)
            return
        }
        if let object = try? container.decode([String: OpenAIRealtimeToolJSONValue].self) {
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
