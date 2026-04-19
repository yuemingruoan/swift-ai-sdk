import Foundation

public struct OpenAIAPIConfiguration: Equatable, Sendable {
    public var apiKey: String
    public var baseURL: URL

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }
}

public enum OpenAITransportError: Error, Equatable, Sendable {
    case invalidResponse
    case unsuccessfulStatusCode(Int)
}

public protocol OpenAIHTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: OpenAIHTTPSession {}

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

public struct OpenAIResponsesRequestBuilder: Sendable {
    public let configuration: OpenAIAPIConfiguration

    public init(configuration: OpenAIAPIConfiguration) {
        self.configuration = configuration
    }

    public func makeURLRequest(for request: OpenAIResponseRequest) throws -> URLRequest {
        let endpoint = configuration.baseURL.appendingPathComponent("responses")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        return urlRequest
    }

    public func makeStreamingURLRequest(for request: OpenAIResponseRequest) throws -> URLRequest {
        try makeURLRequest(
            for: OpenAIResponseRequest(
                model: request.model,
                input: request.input,
                previousResponseID: request.previousResponseID,
                stream: true
            )
        )
    }
}

public struct URLSessionOpenAIResponsesTransport: OpenAIResponsesTransport, Sendable {
    private let builder: OpenAIResponsesRequestBuilder
    private let session: any OpenAIHTTPSession

    public init(
        configuration: OpenAIAPIConfiguration,
        session: any OpenAIHTTPSession = URLSession.shared
    ) {
        self.builder = OpenAIResponsesRequestBuilder(configuration: configuration)
        self.session = session
    }

    public func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse {
        let urlRequest = try builder.makeURLRequest(for: request)
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITransportError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAITransportError.unsuccessfulStatusCode(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(OpenAIResponse.self, from: data)
    }
}

public protocol OpenAIResponsesStreamingTransport: Sendable {
    func streamResponse(_ request: OpenAIResponseRequest) -> AsyncThrowingStream<OpenAIResponseStreamEvent, Error>
}

public struct OpenAIResponseTextDeltaEvent: Codable, Equatable, Sendable {
    public var itemID: String
    public var outputIndex: Int
    public var contentIndex: Int
    public var delta: String
    public var sequenceNumber: Int

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

public enum OpenAIResponseStreamEvent: Equatable, Sendable {
    case responseCreated(OpenAIResponse)
    case outputTextDelta(OpenAIResponseTextDeltaEvent)
    case responseCompleted(OpenAIResponse)
}

public struct URLSessionOpenAIResponsesStreamingTransport: OpenAIResponsesStreamingTransport, Sendable {
    private let builder: OpenAIResponsesRequestBuilder
    private let session: any OpenAIHTTPLineStreamingSession

    public init(
        configuration: OpenAIAPIConfiguration,
        session: any OpenAIHTTPLineStreamingSession = URLSession.shared
    ) {
        self.builder = OpenAIResponsesRequestBuilder(configuration: configuration)
        self.session = session
    }

    public func streamResponse(_ request: OpenAIResponseRequest) -> AsyncThrowingStream<OpenAIResponseStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let urlRequest = try builder.makeStreamingURLRequest(for: request)
                    let (lines, response) = try await session.streamLines(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenAITransportError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw OpenAITransportError.unsuccessfulStatusCode(httpResponse.statusCode)
                    }

                    var dataLines: [String] = []
                    for try await line in lines {
                        if line.isEmpty {
                            if let event = try decodeSSEEvent(from: dataLines) {
                                continuation.yield(event)
                            }
                            dataLines.removeAll(keepingCapacity: true)
                            continue
                        }

                        if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }

                    if let event = try decodeSSEEvent(from: dataLines) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private struct OpenAIStreamEventEnvelope: Decodable {
    let type: String
    let response: OpenAIResponse?
}

private func decodeSSEEvent(from dataLines: [String]) throws -> OpenAIResponseStreamEvent? {
    guard !dataLines.isEmpty else {
        return nil
    }

    let data = dataLines.joined(separator: "\n")
    guard data != "[DONE]" else {
        return nil
    }

    let jsonData = Data(data.utf8)
    let envelope = try JSONDecoder().decode(OpenAIStreamEventEnvelope.self, from: jsonData)

    switch envelope.type {
    case "response.created":
        guard let response = envelope.response else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "missing response payload"))
        }
        return .responseCreated(response)
    case "response.output_text.delta":
        return .outputTextDelta(try JSONDecoder().decode(OpenAIResponseTextDeltaEvent.self, from: jsonData))
    case "response.completed":
        guard let response = envelope.response else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "missing response payload"))
        }
        return .responseCompleted(response)
    default:
        return nil
    }
}
