/// Storage stays protocol-only at the SDK layer.
///
/// Platform-bound secure storage implementations such as Apple Keychain should live in
/// a separate adapter target so the core runtime and auth modules remain cross-platform.
public protocol OpenAITokenStore: Sendable {
    func loadTokens() async throws -> OpenAIAuthTokens?
    func saveTokens(_ tokens: OpenAIAuthTokens) async throws
    func clearTokens() async throws
}
