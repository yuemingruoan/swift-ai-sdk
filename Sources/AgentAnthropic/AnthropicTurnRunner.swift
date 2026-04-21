import AgentCore
import Foundation

/// Configuration for the high-level Anthropic turn runner.
public struct AnthropicTurnRunnerConfiguration: Equatable, Sendable {
    public var model: String
    public var maxTokens: Int
    public var tools: [ToolDescriptor]

    /// Creates configuration for a one-turn Anthropic Messages runner.
    /// - Parameters:
    ///   - model: Model identifier sent to the Messages API.
    ///   - maxTokens: Output token budget for the request.
    ///   - tools: Tool descriptors exposed to the model.
    public init(
        model: String,
        maxTokens: Int,
        tools: [ToolDescriptor] = []
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.tools = tools
    }
}

/// High-level one-turn runner built on ``AnthropicMessagesClient``.
public struct AnthropicTurnRunner: AgentTurnRunner, Sendable {
    public let client: AnthropicMessagesClient
    public let configuration: AnthropicTurnRunnerConfiguration
    public let executor: ToolExecutor?

    /// Creates a one-turn Anthropic runner.
    /// - Parameters:
    ///   - client: High-level Anthropic client used for request execution.
    ///   - configuration: Runner configuration describing model and tool behavior.
    ///   - executor: Optional tool executor used when the model emits tool calls.
    public init(
        client: AnthropicMessagesClient,
        configuration: AnthropicTurnRunnerConfiguration,
        executor: ToolExecutor? = nil
    ) {
        self.client = client
        self.configuration = configuration
        self.executor = executor
    }

    /// Runs one Anthropic Messages turn and yields provider-neutral events.
    /// - Parameter input: Provider-neutral input messages for the turn.
    /// - Returns: A stream of provider-neutral events emitted for the turn.
    /// - Throws: An error if the request cannot be constructed from the supplied messages.
    public func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let request = try AnthropicMessagesRequest(
            model: configuration.model,
            maxTokens: configuration.maxTokens,
            messages: input,
            tools: configuration.tools
        )

        return client.projectedResponseEvents(
            request,
            using: executor
        )
    }
}
