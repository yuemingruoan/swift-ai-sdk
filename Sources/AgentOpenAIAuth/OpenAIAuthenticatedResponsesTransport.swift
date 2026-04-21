import AgentOpenAI
import Foundation

public struct OpenAIAuthenticatedAPIConfiguration: Sendable {
    public var baseURL: URL
    public var compatibilityProfile: OpenAICompatibilityProfile
    public var originator: String?
    public var userAgent: String?
    public var acceptLanguage: String?

    public init(
        baseURL: URL = URL(string: "https://chatgpt.com/backend-api/codex")!,
        compatibilityProfile: OpenAICompatibilityProfile = .chatGPTCodexOAuth,
        originator: String? = "codex_cli_rs",
        userAgent: String? = nil,
        acceptLanguage: String? = nil
    ) {
        self.baseURL = baseURL
        self.compatibilityProfile = compatibilityProfile
        self.originator = originator
        self.userAgent = userAgent
        self.acceptLanguage = acceptLanguage
    }
}

public enum OpenAIAuthenticatedTransportError: Error, Equatable, Sendable {
    case missingChatGPTAccountID
}

public struct OpenAIAuthenticatedResponsesRequestBuilder: Sendable {
    public let configuration: OpenAIAuthenticatedAPIConfiguration
    public let tokenProvider: any OpenAITokenProvider

    public init(
        configuration: OpenAIAuthenticatedAPIConfiguration,
        tokenProvider: any OpenAITokenProvider
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
    }

    public func makeURLRequest(for request: OpenAIResponseRequest) async throws -> URLRequest {
        let tokens = try await tokenProvider.currentTokens()
        return try makeURLRequest(for: request, tokens: tokens, streaming: false)
    }

    public func makeStreamingURLRequest(for request: OpenAIResponseRequest) async throws -> URLRequest {
        let tokens = try await tokenProvider.currentTokens()
        return try makeURLRequest(for: request, tokens: tokens, streaming: true)
    }

    func makeURLRequest(
        for request: OpenAIResponseRequest,
        tokens: OpenAIAuthTokens,
        streaming: Bool
    ) throws -> URLRequest {
        let transformed = OpenAIChatGPTRequestTransform(
            profile: configuration.compatibilityProfile
        ).transform(request)
        let endpoint = configuration.baseURL.appendingPathComponent("responses")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(
            streaming ? "text/event-stream" : "application/json",
            forHTTPHeaderField: "Accept"
        )

        if let userAgent = configuration.userAgent, !userAgent.isEmpty {
            urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        if let acceptLanguage = configuration.acceptLanguage, !acceptLanguage.isEmpty {
            urlRequest.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        }

        if configuration.compatibilityProfile.requiresChatGPTCodexTransform {
            guard let accountID = tokens.chatGPTAccountID, !accountID.isEmpty else {
                throw OpenAIAuthenticatedTransportError.missingChatGPTAccountID
            }
            urlRequest.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
            urlRequest.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
            if let originator = configuration.originator, !originator.isEmpty {
                urlRequest.setValue(originator, forHTTPHeaderField: "originator")
            }
        }

        urlRequest.httpBody = try JSONEncoder().encode(transformed)
        return urlRequest
    }
}

public struct URLSessionOpenAIAuthenticatedResponsesTransport: OpenAIResponsesTransport, Sendable {
    private let builder: OpenAIAuthenticatedResponsesRequestBuilder
    private let session: any OpenAIHTTPSession

    public init(
        configuration: OpenAIAuthenticatedAPIConfiguration,
        tokenProvider: any OpenAITokenProvider,
        session: any OpenAIHTTPSession = URLSession.shared
    ) {
        self.builder = OpenAIAuthenticatedResponsesRequestBuilder(
            configuration: configuration,
            tokenProvider: tokenProvider
        )
        self.session = session
    }

    public func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse {
        let initialTokens = try await builder.tokenProvider.currentTokens()
        let initialRequest = try builder.makeURLRequest(
            for: request,
            tokens: initialTokens,
            streaming: false
        )
        let (data, response) = try await session.data(for: initialRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITransportError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            let refreshedTokens = try await builder.tokenProvider.refreshTokens(reason: .unauthorized)
            let retryRequest = try builder.makeURLRequest(
                for: request,
                tokens: refreshedTokens,
                streaming: false
            )
            let (retryData, retryResponse) = try await session.data(for: retryRequest)
            return try decodeResponse(data: retryData, response: retryResponse)
        }

        return try decodeResponse(data: data, response: response)
    }

    private func decodeResponse(data: Data, response: URLResponse) throws -> OpenAIResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITransportError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAITransportError.unsuccessfulStatusCode(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(OpenAIResponse.self, from: data)
    }
}

public struct URLSessionOpenAIAuthenticatedResponsesStreamingTransport: OpenAIResponsesStreamingTransport, Sendable {
    private let builder: OpenAIAuthenticatedResponsesRequestBuilder
    private let session: any OpenAIHTTPLineStreamingSession

    public init(
        configuration: OpenAIAuthenticatedAPIConfiguration,
        tokenProvider: any OpenAITokenProvider,
        session: any OpenAIHTTPLineStreamingSession = URLSession.shared
    ) {
        self.builder = OpenAIAuthenticatedResponsesRequestBuilder(
            configuration: configuration,
            tokenProvider: tokenProvider
        )
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
        let initialTokens = try await builder.tokenProvider.currentTokens()
        let initialRequest = try builder.makeURLRequest(
            for: request,
            tokens: initialTokens,
            streaming: true
        )
        let (lines, response) = try await session.streamLines(for: initialRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITransportError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            let refreshedTokens = try await builder.tokenProvider.refreshTokens(reason: .unauthorized)
            let retryRequest = try builder.makeURLRequest(
                for: request,
                tokens: refreshedTokens,
                streaming: true
            )
            let (retryLines, retryResponse) = try await session.streamLines(for: retryRequest)
            try await consume(lines: retryLines, response: retryResponse, continuation: continuation)
            return
        }

        try await consume(lines: lines, response: response, continuation: continuation)
    }

    private func consume(
        lines: AsyncThrowingStream<String, Error>,
        response: URLResponse,
        continuation: AsyncThrowingStream<OpenAIResponseStreamEvent, Error>.Continuation
    ) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITransportError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAITransportError.unsuccessfulStatusCode(httpResponse.statusCode)
        }

        var dataLines: [String] = []
        for try await line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.isEmpty {
                if let event = try decodeAuthenticatedSSEEvent(from: dataLines) {
                    continuation.yield(event)
                }
                dataLines.removeAll(keepingCapacity: true)
                continue
            }

            if trimmedLine.hasPrefix("event:") {
                if let event = try decodeAuthenticatedSSEEvent(from: dataLines) {
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

        if let event = try decodeAuthenticatedSSEEvent(from: dataLines) {
            continuation.yield(event)
        }
    }
}

private func decodeAuthenticatedSSEEvent(
    from dataLines: [String]
) throws -> OpenAIResponseStreamEvent? {
    guard !dataLines.isEmpty else {
        return nil
    }

    let data = dataLines.joined(separator: "\n")
    guard data != "[DONE]" else {
        return nil
    }

    let jsonData = Data(data.utf8)
    let envelope = try JSONDecoder().decode(OpenAIAuthenticatedStreamEventEnvelope.self, from: jsonData)

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

private struct OpenAIAuthenticatedStreamEventEnvelope: Decodable {
    let type: String
    let response: OpenAIResponse?
}
