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
