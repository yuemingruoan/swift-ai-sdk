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
        try await send(
            OpenAIRealtimeEvent(
                type: "session.update",
                payload: [
                    "session": .object([
                        "instructions": .string(instructions),
                    ]),
                ]
            )
        )
    }

    public func sendUserText(_ text: String) async throws {
        try await send(
            OpenAIRealtimeEvent(
                type: "conversation.item.create",
                payload: [
                    "item": .object([
                        "type": .string("message"),
                        "role": .string("user"),
                        "content": .array([
                            .object([
                                "type": .string("input_text"),
                                "text": .string(text),
                            ]),
                        ]),
                    ]),
                ]
            )
        )
    }

    public func createResponse() async throws {
        try await send(OpenAIRealtimeEvent(type: "response.create"))
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

        case "response.completed":
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
