import Foundation

public let OpenAIResponsesWebSocketBetaHeaderValue = "responses_websockets=2026-02-06"

public struct OpenAIResponsesWebSocketConfiguration: Equatable, Sendable {
    public var authorizationValue: String
    public var baseURL: URL
    public var additionalHeaders: [String: String]
    public var clientRequestID: String?
    public var betaHeaderValue: String?

    public init(
        authorizationValue: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        additionalHeaders: [String: String] = [:],
        clientRequestID: String? = nil,
        betaHeaderValue: String? = OpenAIResponsesWebSocketBetaHeaderValue
    ) {
        self.authorizationValue = authorizationValue
        self.baseURL = baseURL
        self.additionalHeaders = additionalHeaders
        self.clientRequestID = clientRequestID
        self.betaHeaderValue = betaHeaderValue
    }

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        additionalHeaders: [String: String] = [:],
        clientRequestID: String? = nil,
        betaHeaderValue: String? = OpenAIResponsesWebSocketBetaHeaderValue
    ) {
        self.init(
            authorizationValue: "Bearer \(apiKey)",
            baseURL: baseURL,
            additionalHeaders: additionalHeaders,
            clientRequestID: clientRequestID,
            betaHeaderValue: betaHeaderValue
        )
    }
}

public struct OpenAIResponsesWebSocketRequestBuilder: Sendable {
    public let configuration: OpenAIResponsesWebSocketConfiguration

    public init(configuration: OpenAIResponsesWebSocketConfiguration) {
        self.configuration = configuration
    }

    public func makeURLRequest() throws -> URLRequest {
        var urlRequest = URLRequest(url: try websocketURL())
        urlRequest.setValue(configuration.authorizationValue, forHTTPHeaderField: "Authorization")

        if let clientRequestID = configuration.clientRequestID, !clientRequestID.isEmpty {
            urlRequest.setValue(clientRequestID, forHTTPHeaderField: "x-client-request-id")
        }
        if let betaHeaderValue = configuration.betaHeaderValue, !betaHeaderValue.isEmpty {
            urlRequest.setValue(betaHeaderValue, forHTTPHeaderField: "OpenAI-Beta")
        }
        for (name, value) in configuration.additionalHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return urlRequest
    }

    public func makeTextMessage(for request: OpenAIResponseRequest) throws -> String {
        let data = try JSONEncoder().encode(
            OpenAIResponseCreateWebSocketRequest(request: request)
        )
        return String(decoding: data, as: UTF8.self)
    }

    private func websocketURL() throws -> URL {
        guard var components = URLComponents(
            url: configuration.baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }

        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        case "wss", "ws":
            break
        default:
            throw URLError(.badURL)
        }

        let path = components.path.isEmpty ? "/" : components.path
        if !path.hasSuffix("/responses") {
            components.path = path.hasSuffix("/") ? path + "responses" : path + "/responses"
        }

        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }
}

public struct OpenAIResponseCreateWebSocketRequest: Codable, Equatable, Sendable {
    public var type: String
    public var model: String
    public var input: [OpenAIResponseInputItem]
    public var instructions: String?
    public var previousResponseID: String?
    public var store: Bool?
    public var promptCacheKey: String?
    public var stream: Bool?
    public var tools: [OpenAIResponseTool]?
    public var toolChoice: OpenAIResponseToolChoice?

    public init(request: OpenAIResponseRequest) {
        self.type = "response.create"
        self.model = request.model
        self.input = request.input
        self.instructions = request.instructions
        self.previousResponseID = request.previousResponseID
        self.store = request.store
        self.promptCacheKey = request.promptCacheKey
        self.stream = request.stream ?? true
        self.tools = request.tools
        self.toolChoice = request.toolChoice
    }

    enum CodingKeys: String, CodingKey {
        case type
        case model
        case input
        case instructions
        case previousResponseID = "previous_response_id"
        case store
        case promptCacheKey = "prompt_cache_key"
        case stream
        case tools
        case toolChoice = "tool_choice"
    }
}

public struct URLSessionOpenAIResponsesWebSocketTransport: OpenAIResponsesStreamingTransport, Sendable {
    private let builder: OpenAIResponsesWebSocketRequestBuilder
    private let session: any OpenAIWebSocketSession

    public init(
        configuration: OpenAIResponsesWebSocketConfiguration,
        session: any OpenAIWebSocketSession = URLSession.shared
    ) {
        self.builder = OpenAIResponsesWebSocketRequestBuilder(configuration: configuration)
        self.session = session
    }

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
        let urlRequest = try builder.makeURLRequest()
        let connection = session.makeConnection(with: urlRequest)

        do {
            await connection.connect()
            try await connection.send(text: builder.makeTextMessage(for: request))

            while true {
                let text = try await connection.receiveText()
                guard let event = try decodeWebSocketResponseEvent(from: text) else {
                    continue
                }
                continuation.yield(event)

                if event.isTerminal {
                    break
                }
            }

            await connection.cancel()
        } catch {
            await connection.cancel()
            throw error
        }
    }
}

private extension OpenAIResponseStreamEvent {
    var isTerminal: Bool {
        switch self {
        case .responseFailed, .responseIncomplete, .error, .responseCompleted:
            return true
        case .responseCreated, .outputTextDelta, .outputItemDone:
            return false
        }
    }
}

private struct OpenAIWebSocketEventEnvelope: Decodable {
    let type: String
    let response: OpenAIResponse?
}

private func decodeWebSocketResponseEvent(from text: String) throws -> OpenAIResponseStreamEvent? {
    let jsonData = Data(text.utf8)
    let envelope = try JSONDecoder().decode(OpenAIWebSocketEventEnvelope.self, from: jsonData)

    switch envelope.type {
    case "response.created":
        guard let response = envelope.response else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "missing response payload")
            )
        }
        return .responseCreated(response)
    case "response.output_text.delta":
        return .outputTextDelta(try JSONDecoder().decode(OpenAIResponseTextDeltaEvent.self, from: jsonData))
    case "response.output_item.done":
        return .outputItemDone(try JSONDecoder().decode(OpenAIResponseOutputItemDoneEvent.self, from: jsonData))
    case "response.failed":
        guard let response = envelope.response else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "missing response payload")
            )
        }
        return .responseFailed(response)
    case "response.incomplete":
        guard let response = envelope.response else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "missing response payload")
            )
        }
        return .responseIncomplete(response)
    case "error":
        return .error(try JSONDecoder().decode(OpenAIResponseStreamErrorEvent.self, from: jsonData))
    case "response.completed":
        guard let response = envelope.response else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "missing response payload")
            )
        }
        return .responseCompleted(response)
    default:
        return nil
    }
}
