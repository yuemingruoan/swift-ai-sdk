import AgentOpenAI

public struct OpenAIChatGPTRequestTransform: Sendable {
    public var profile: OpenAICompatibilityProfile

    public init(profile: OpenAICompatibilityProfile) {
        self.profile = profile
    }

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
