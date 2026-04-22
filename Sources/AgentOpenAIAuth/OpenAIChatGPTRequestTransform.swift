import OpenAIResponsesAPI

/// Applies compatibility rewrites needed by ChatGPT/Codex-style Responses backends.
public struct OpenAIChatGPTRequestTransform: Sendable {
    public var profile: OpenAICompatibilityProfile

    /// Creates a transform for a compatibility profile.
    /// - Parameter profile: Compatibility profile controlling which request rewrites are applied.
    public init(profile: OpenAICompatibilityProfile) {
        self.profile = profile
    }

    /// Rewrites a standard Responses request into the profile-specific request shape.
    /// - Parameter request: Standard Responses request payload.
    /// - Returns: The transformed request payload for the configured compatibility profile.
    public func transform(_ request: OpenAIResponseRequest) -> OpenAIResponseRequest {
        guard profile.requiresChatGPTCodexTransform else {
            return request
        }

        return OpenAIResponseRequest(
            model: request.model,
            input: request.input,
            instructions: request.instructions ?? "",
            previousResponseID: nil,
            store: false,
            promptCacheKey: request.promptCacheKey,
            stream: true,
            tools: request.tools,
            toolChoice: request.toolChoice
        )
    }
}
