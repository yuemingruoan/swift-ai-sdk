import AgentCore

/// Reason for requesting a fresh access token from a token provider.
public enum OpenAITokenRefreshReason: Equatable, Sendable {
    case unauthorized
    case expired
}

/// Supplies current tokens and optional refresh behavior for authenticated OpenAI-compatible transports.
public protocol OpenAITokenProvider: Sendable {
    /// Returns the current token set available to the host.
    /// - Returns: The token bundle currently available for authenticated requests.
    /// - Throws: An error if the host cannot provide tokens.
    func currentTokens() async throws -> OpenAIAuthTokens
    /// Refreshes the token set after the supplied failure reason.
    /// - Parameter reason: Reason the caller is requesting a refreshed token set.
    /// - Returns: A newly refreshed token bundle.
    /// - Throws: An error if refresh is unsupported or the refresh flow fails.
    func refreshTokens(reason: OpenAITokenRefreshReason) async throws -> OpenAIAuthTokens
}

/// Thin token provider for hosts that already own token persistence and refresh policy.
public struct OpenAIExternalTokenProvider: OpenAITokenProvider, Sendable {
    private let tokens: OpenAIAuthTokens

    /// Creates a token provider that always returns the supplied token set.
    /// - Parameter tokens: Token bundle returned by `currentTokens()`.
    public init(tokens: OpenAIAuthTokens) {
        self.tokens = tokens
    }

    /// Returns the configured tokens without additional lookup.
    /// - Returns: The token bundle supplied when the provider was created.
    public func currentTokens() async throws -> OpenAIAuthTokens {
        tokens
    }

    /// Always throws because this provider does not implement refresh.
    /// - Parameter reason: Reason the caller requested refreshed tokens.
    /// - Returns: Never returns successfully.
    /// - Throws: ``AgentAuthError/refreshUnsupported``.
    public func refreshTokens(reason _: OpenAITokenRefreshReason) async throws -> OpenAIAuthTokens {
        throw AgentAuthError.refreshUnsupported
    }
}
