import AgentCore
import Foundation

public protocol OpenAIResponsesTransport: Sendable {
    func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse
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
