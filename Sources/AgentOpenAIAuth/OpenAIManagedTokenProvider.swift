import AgentCore
import Foundation

/// Token provider that reads persisted tokens, refreshes them when needed, and saves the refreshed value.
public struct OpenAIManagedTokenProvider: OpenAITokenProvider, Sendable {
    public let store: any OpenAITokenStore
    public let refresher: any OpenAITokenRefresher
    public let clock: @Sendable () -> Date

    /// Creates a managed token provider around a store and refresher pair.
    public init(
        store: any OpenAITokenStore,
        refresher: any OpenAITokenRefresher,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.refresher = refresher
        self.clock = clock
    }

    /// Returns the current tokens, refreshing them first when `expiresAt` has already passed.
    public func currentTokens() async throws -> OpenAIAuthTokens {
        let tokens = try await loadRequiredTokens()
        guard shouldRefresh(tokens) else {
            return tokens
        }

        return try await refreshAndPersist(current: tokens, reason: .expired)
    }

    /// Forces a refresh cycle and persists the newly returned tokens.
    public func refreshTokens(reason: OpenAITokenRefreshReason) async throws -> OpenAIAuthTokens {
        let tokens = try await loadRequiredTokens()
        return try await refreshAndPersist(current: tokens, reason: reason)
    }

    private func loadRequiredTokens() async throws -> OpenAIAuthTokens {
        guard let tokens = try await store.loadTokens() else {
            throw AgentAuthError.missingCredentials("tokens")
        }
        return tokens
    }

    private func shouldRefresh(_ tokens: OpenAIAuthTokens) -> Bool {
        guard let expiresAt = tokens.expiresAt else {
            return false
        }
        return expiresAt <= clock()
    }

    private func refreshAndPersist(
        current: OpenAIAuthTokens,
        reason: OpenAITokenRefreshReason
    ) async throws -> OpenAIAuthTokens {
        let refreshed = try await refresher.refreshTokens(
            current: current,
            reason: reason
        )
        try await store.saveTokens(refreshed)
        return refreshed
    }
}
