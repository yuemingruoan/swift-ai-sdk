import AgentOpenAI

public struct OpenAICompatibilityProfile: Equatable, Sendable {
    public var responsesFollowUpStrategy: OpenAIResponsesFollowUpStrategy
    public var requiresChatGPTCodexTransform: Bool

    public init(
        responsesFollowUpStrategy: OpenAIResponsesFollowUpStrategy,
        requiresChatGPTCodexTransform: Bool = false
    ) {
        self.responsesFollowUpStrategy = responsesFollowUpStrategy
        self.requiresChatGPTCodexTransform = requiresChatGPTCodexTransform
    }

    public static let openAI = Self(
        responsesFollowUpStrategy: .previousResponseID
    )

    public static let newAPI = Self(
        responsesFollowUpStrategy: .replayInput
    )

    public static let sub2api = Self(
        responsesFollowUpStrategy: .replayInput
    )

    public static let chatGPTCodexOAuth = Self(
        responsesFollowUpStrategy: .replayInput,
        requiresChatGPTCodexTransform: true
    )
}
