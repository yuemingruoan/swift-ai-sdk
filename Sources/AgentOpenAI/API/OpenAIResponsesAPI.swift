@_exported import AgentCore

/// Provider-native OpenAI Responses request, response, streaming, transport, and built-in tool models.
public enum OpenAIResponsesAPIModule {}

/// Strategy used by higher-level runtimes when constructing OpenAI follow-up requests after tool calls.
public enum OpenAIResponsesFollowUpStrategy: Equatable, Sendable {
    case previousResponseID
    case replayInput
}
