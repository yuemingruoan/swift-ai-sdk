public protocol OpenAITokenRefresher: Sendable {
    func refreshTokens(
        current: OpenAIAuthTokens,
        reason: OpenAITokenRefreshReason
    ) async throws -> OpenAIAuthTokens
}
