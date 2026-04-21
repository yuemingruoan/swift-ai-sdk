import AgentCore
import Foundation

public struct AnthropicTurnRunnerConfiguration: Equatable, Sendable {
    public var model: String
    public var maxTokens: Int
    public var tools: [ToolDescriptor]

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

public struct AnthropicTurnRunner: AgentTurnRunner, Sendable {
    public let client: AnthropicMessagesClient
    public let configuration: AnthropicTurnRunnerConfiguration
    public let executor: ToolExecutor?

    public init(
        client: AnthropicMessagesClient,
        configuration: AnthropicTurnRunnerConfiguration,
        executor: ToolExecutor? = nil
    ) {
        self.client = client
        self.configuration = configuration
        self.executor = executor
    }

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
