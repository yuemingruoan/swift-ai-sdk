import Foundation

/// Provider identifiers used by SDK-facing transport, auth, decoding, and streaming errors.
public enum AgentProviderID: String, Codable, Equatable, Sendable {
    case openAI = "openai"
    case anthropic
}

/// Errors surfaced when a provider returns a non-successful HTTP response.
public enum AgentProviderError: Error, Equatable, Sendable {
    case unsuccessfulResponse(provider: AgentProviderID, statusCode: Int)
}

/// Errors surfaced while building or executing transport requests.
public enum AgentTransportError: Error, Equatable, Sendable {
    case invalidResponse(provider: AgentProviderID)
    case requestFailed(provider: AgentProviderID, description: String)
}

/// Errors surfaced while decoding provider payloads or projecting them into SDK shapes.
public enum AgentDecodingError: Error, Equatable, Sendable {
    case responseBody(provider: AgentProviderID, description: String)
    case responseProjection(provider: AgentProviderID, description: String)
}

/// Errors surfaced by token providers, OAuth flows, and authenticated transports.
public enum AgentAuthError: Error, Equatable, Sendable {
    case missingCredentials(String)
    case unauthorized(provider: AgentProviderID?)
    case refreshUnsupported
    case tokenProviderFailure(description: String)
    case unsupportedAuthorizationMethod(String)
    case unknownAuthorizationSession
    case missingBrowserRedirectURL
    case callbackURLRequired
    case missingAuthorizationCode
    case stateMismatch
    case callbackError(code: String, description: String?)
    case deviceCodeTimedOut
    case invalidConfiguration(String)
}

/// Errors surfaced while consuming provider streaming responses.
public enum AgentStreamError: Error, Equatable, Sendable {
    case eventDecodingFailed(provider: AgentProviderID)
    case responseFailed(provider: AgentProviderID, status: String)
    case serverError(provider: AgentProviderID, type: String, code: String?, message: String?)
}
