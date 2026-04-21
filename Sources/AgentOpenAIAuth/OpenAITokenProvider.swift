public enum OpenAITokenRefreshReason: Equatable, Sendable {
    case unauthorized
    case expired
}

public enum OpenAITokenProviderError: Error, Equatable, Sendable {
    case refreshUnsupported
    case missingTokens
}

public protocol OpenAITokenProvider: Sendable {
    func currentTokens() async throws -> OpenAIAuthTokens
    func refreshTokens(reason: OpenAITokenRefreshReason) async throws -> OpenAIAuthTokens
}

public struct OpenAIExternalTokenProvider: OpenAITokenProvider, Sendable {
    private let tokens: OpenAIAuthTokens

    public init(tokens: OpenAIAuthTokens) {
        self.tokens = tokens
    }

    public func currentTokens() async throws -> OpenAIAuthTokens {
        tokens
    }

    public func refreshTokens(reason _: OpenAITokenRefreshReason) async throws -> OpenAIAuthTokens {
        throw OpenAITokenProviderError.refreshUnsupported
    }
}
