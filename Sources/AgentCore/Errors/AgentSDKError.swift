import Foundation

public enum AgentProviderID: String, Codable, Equatable, Sendable {
    case openAI = "openai"
    case anthropic
}

public enum AgentProviderError: Error, Equatable, Sendable {
    case unsuccessfulResponse(provider: AgentProviderID, statusCode: Int)
}

public enum AgentTransportError: Error, Equatable, Sendable {
    case invalidResponse(provider: AgentProviderID)
    case requestFailed(provider: AgentProviderID, description: String)
}

public enum AgentDecodingError: Error, Equatable, Sendable {
    case responseBody(provider: AgentProviderID, description: String)
    case responseProjection(provider: AgentProviderID, description: String)
}

public enum AgentAuthError: Error, Equatable, Sendable {
    case missingCredentials(String)
    case unauthorized(provider: AgentProviderID?)
    case refreshUnsupported
    case tokenProviderFailure(description: String)
}

public enum AgentStreamError: Error, Equatable, Sendable {
    case eventDecodingFailed(provider: AgentProviderID)
    case responseFailed(provider: AgentProviderID, status: String)
    case serverError(provider: AgentProviderID, type: String, code: String?, message: String?)
}
