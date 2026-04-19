import AgentCore
import Foundation

public protocol OpenAIResponsesTransport: Sendable {
    func createResponse(_ request: OpenAIResponseRequest) async throws -> OpenAIResponse
}

public struct OpenAIResponsesClient: Sendable {
    private let transport: any OpenAIResponsesTransport

    public init(transport: any OpenAIResponsesTransport) {
        self.transport = transport
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
}
