import AgentCore
import Foundation

/// Configuration for the high-level Anthropic turn runner.
public struct AnthropicTurnRunnerConfiguration: Equatable, Sendable {
    public var model: String
    public var maxTokens: Int
    public var tools: [ToolDescriptor]
    public var stream: Bool
    public var projectionOptions: AnthropicProjectionOptions

    /// Creates configuration for a one-turn Anthropic Messages runner.
    /// - Parameters:
    ///   - model: Model identifier sent to the Messages API.
    ///   - maxTokens: Output token budget for the request.
    ///   - tools: Tool descriptors exposed to the model.
    ///   - stream: Whether the runner should prefer streaming execution.
    ///   - projectionOptions: Policy used when projecting raw Anthropic output into provider-neutral messages.
    public init(
        model: String,
        maxTokens: Int,
        tools: [ToolDescriptor] = [],
        stream: Bool = false,
        projectionOptions: AnthropicProjectionOptions = .omitThinking
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.tools = tools
        self.stream = stream
        self.projectionOptions = projectionOptions
    }
}

/// High-level one-turn runner built on ``AnthropicMessagesClient``.
public struct AnthropicTurnRunner: AgentTurnRunner, Sendable {
    public let client: AnthropicMessagesClient
    public let configuration: AnthropicTurnRunnerConfiguration
    public let executor: ToolExecutor?
    public let middleware: AgentMiddlewareStack

    /// Creates a one-turn Anthropic runner.
    /// - Parameters:
    ///   - client: High-level Anthropic client used for request execution.
    ///   - configuration: Runner configuration describing model and tool behavior.
    ///   - executor: Optional tool executor used when the model emits tool calls.
    public init(
        client: AnthropicMessagesClient,
        configuration: AnthropicTurnRunnerConfiguration,
        executor: ToolExecutor? = nil,
        middleware: AgentMiddlewareStack = AgentMiddlewareStack()
    ) {
        self.client = client
        self.configuration = configuration
        self.executor = executor
        self.middleware = middleware
    }

    /// Runs one Anthropic Messages turn and yields provider-neutral events.
    /// - Parameter input: Provider-neutral input messages for the turn.
    /// - Returns: A stream of provider-neutral events emitted for the turn.
    /// - Throws: An error if the request cannot be constructed from the supplied messages.
    public func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let requestContext = try await prepareRequestContext(input: input)
                    let request = try AnthropicMessagesRequest(
                        model: requestContext.model,
                        maxTokens: configuration.maxTokens,
                        messages: requestContext.input,
                        tools: requestContext.tools,
                        stream: requestContext.stream
                    )

                    if requestContext.stream {
                        let baseStream = client.projectedResponseEvents(
                            request,
                            using: executor,
                            stream: true,
                            projectionOptions: configuration.projectionOptions
                        )
                        try await streamProcessedEvents(
                            from: baseStream,
                            model: requestContext.model,
                            into: continuation
                        )
                    } else if let executor {
                        let baseStream = client.projectedResponseEvents(
                            request,
                            using: executor,
                            projectionOptions: configuration.projectionOptions
                        )
                        try await streamProcessedEvents(
                            from: baseStream,
                            model: requestContext.model,
                            into: continuation
                        )
                    } else {
                        let projection = try await client.createProjectedResponse(
                            request,
                            options: configuration.projectionOptions
                        )
                        let responseContext = try await middleware.processModelResponse(
                            AgentModelResponseContext(
                                provider: .anthropic,
                                model: requestContext.model,
                                messages: projection.messages,
                                toolCalls: projection.toolCalls.map {
                                    AgentToolCall(callID: $0.callID, invocation: $0.invocation)
                                },
                                metadata: [
                                    "maxTokens": String(configuration.maxTokens),
                                ]
                            )
                        )
                        await middleware.recordAuditEvent(.modelResponseCompleted(.init(context: responseContext)))

                        for toolCall in responseContext.toolCalls {
                            continuation.yield(.toolCall(toolCall))
                        }
                        if !responseContext.messages.isEmpty {
                            continuation.yield(.messagesCompleted(responseContext.messages))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func prepareRequestContext(
        input: [AgentMessage]
    ) async throws -> AgentModelRequestContext {
        let context = try await middleware.prepareModelRequest(
            AgentModelRequestContext(
                provider: .anthropic,
                model: configuration.model,
                input: input,
                tools: configuration.tools,
                stream: configuration.stream,
                metadata: [
                    "maxTokens": String(configuration.maxTokens),
                ]
            )
        )
        await middleware.recordAuditEvent(.modelRequestStarted(.init(context: context)))
        return context
    }

    private func streamProcessedEvents(
        from baseStream: AsyncThrowingStream<AgentStreamEvent, Error>,
        model: String,
        into continuation: AsyncThrowingStream<AgentStreamEvent, Error>.Continuation
    ) async throws {
        var toolCalls: [AgentToolCall] = []

        for try await event in baseStream {
            switch event {
            case .toolCall(let toolCall):
                toolCalls.append(toolCall)
                continuation.yield(.toolCall(toolCall))

            case .messagesCompleted(let messages):
                let responseContext = try await middleware.processModelResponse(
                    AgentModelResponseContext(
                        provider: .anthropic,
                        model: model,
                        messages: messages,
                        toolCalls: toolCalls,
                        metadata: [
                            "maxTokens": String(configuration.maxTokens),
                        ]
                    )
                )
                await middleware.recordAuditEvent(.modelResponseCompleted(.init(context: responseContext)))
                if !responseContext.messages.isEmpty {
                    continuation.yield(.messagesCompleted(responseContext.messages))
                }
                toolCalls.removeAll()

            default:
                continuation.yield(event)
            }
        }
    }
}
