import AgentCore
import OpenAIResponsesAPI
import Foundation

/// Configuration for the high-level OpenAI Responses turn runner.
public struct OpenAIResponsesTurnRunnerConfiguration: Equatable, Sendable {
    public var model: String
    public var previousResponseID: String?
    public var tools: [ToolDescriptor]
    public var toolChoice: OpenAIResponseToolChoice?
    public var stream: Bool

    /// Creates configuration for a one-turn OpenAI Responses runner.
    /// - Parameters:
    ///   - model: Model identifier sent to the Responses API.
    ///   - previousResponseID: Optional previous response identifier used for follow-up requests.
    ///   - tools: Tool descriptors exposed to the model.
    ///   - toolChoice: Optional tool-choice override sent to the Responses API.
    ///   - stream: Whether the runner should prefer streaming execution.
    public init(
        model: String,
        previousResponseID: String? = nil,
        tools: [ToolDescriptor] = [],
        toolChoice: OpenAIResponseToolChoice? = nil,
        stream: Bool = false
    ) {
        self.model = model
        self.previousResponseID = previousResponseID
        self.tools = tools
        self.toolChoice = toolChoice
        self.stream = stream
    }
}

/// High-level one-turn runner built on ``OpenAIResponsesClient``.
public struct OpenAIResponsesTurnRunner: AgentTurnRunner, Sendable {
    public let client: OpenAIResponsesClient
    public let configuration: OpenAIResponsesTurnRunnerConfiguration
    public let executor: ToolExecutor?
    public let middleware: AgentMiddlewareStack

    /// Creates a one-turn Responses runner.
    /// - Parameters:
    ///   - client: High-level Responses client used for request execution.
    ///   - configuration: Runner configuration describing model and tool behavior.
    ///   - executor: Optional tool executor used when the model emits tool calls.
    public init(
        client: OpenAIResponsesClient,
        configuration: OpenAIResponsesTurnRunnerConfiguration,
        executor: ToolExecutor? = nil,
        middleware: AgentMiddlewareStack = AgentMiddlewareStack()
    ) {
        self.client = client
        self.configuration = configuration
        self.executor = executor
        self.middleware = middleware
    }

    /// Runs one Responses turn and yields provider-neutral events.
    /// - Parameter input: Provider-neutral input messages for the turn.
    /// - Returns: A stream of provider-neutral events emitted for the turn.
    /// - Throws: An error if the request cannot be constructed from the supplied messages.
    public func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let requestContext = try await prepareRequestContext(input: input)
                    let request = try OpenAIResponseRequest(
                        model: requestContext.model,
                        messages: requestContext.input,
                        previousResponseID: configuration.previousResponseID,
                        stream: requestContext.stream,
                        tools: requestContext.tools,
                        toolChoice: configuration.toolChoice
                    )

                    if let executor {
                        let baseStream = client.projectedResponseEvents(
                            request,
                            using: executor,
                            stream: requestContext.stream
                        )
                        try await streamProcessedEvents(
                            from: baseStream,
                            model: requestContext.model,
                            into: continuation
                        )
                        return
                    }

                    if requestContext.stream {
                        let baseStream = client.projectedResponseEvents(
                            request,
                            stream: true
                        )

                        try await streamProcessedEvents(
                            from: baseStream,
                            model: requestContext.model,
                            into: continuation
                        )
                        return
                    }

                    let projection = try await client.createProjectedResponse(request)
                    try await emitProcessedResponse(
                        messages: projection.messages,
                        toolCalls: projection.toolCalls.map {
                            AgentToolCall(callID: $0.callID, invocation: $0.invocation)
                        },
                        model: requestContext.model,
                        into: continuation
                    )
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
                provider: .openAI,
                model: configuration.model,
                input: input,
                tools: configuration.tools,
                stream: configuration.stream,
                metadata: [
                    "previousResponseID": configuration.previousResponseID ?? "",
                    "toolChoice": configuration.toolChoice.map(String.init(describing:)) ?? "",
                ]
            )
        )
        await middleware.recordAuditEvent(.modelRequestStarted(.init(context: context)))
        return context
    }

    private func emitProcessedResponse(
        messages: [AgentMessage],
        toolCalls: [AgentToolCall],
        model: String,
        into continuation: AsyncThrowingStream<AgentStreamEvent, Error>.Continuation
    ) async throws {
        let context = try await middleware.processModelResponse(
            AgentModelResponseContext(
                provider: .openAI,
                model: model,
                messages: messages,
                toolCalls: toolCalls
            )
        )
        await middleware.recordAuditEvent(.modelResponseCompleted(.init(context: context)))

        for toolCall in context.toolCalls {
            continuation.yield(.toolCall(toolCall))
        }
        if !context.messages.isEmpty {
            continuation.yield(.messagesCompleted(context.messages))
        }
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
                let context = try await middleware.processModelResponse(
                    AgentModelResponseContext(
                        provider: .openAI,
                        model: model,
                        messages: messages,
                        toolCalls: toolCalls
                    )
                )
                await middleware.recordAuditEvent(.modelResponseCompleted(.init(context: context)))
                if !context.messages.isEmpty {
                    continuation.yield(.messagesCompleted(context.messages))
                }
                toolCalls.removeAll()

            default:
                continuation.yield(event)
            }
        }

        continuation.finish()
    }
}

/// Configuration for the high-level OpenAI Realtime turn runner.
public struct OpenAIRealtimeTurnRunnerConfiguration: Equatable, Sendable {
    public var instructions: String?
    public var tools: [ToolDescriptor]
    public var toolChoice: OpenAIResponseToolChoice?

    /// Creates configuration for a one-turn OpenAI Realtime runner.
    /// - Parameters:
    ///   - instructions: Optional session-level instructions sent before the response is created.
    ///   - tools: Tool descriptors exposed to the Realtime session.
    ///   - toolChoice: Optional tool-choice override sent during session configuration.
    public init(
        instructions: String? = nil,
        tools: [ToolDescriptor] = [],
        toolChoice: OpenAIResponseToolChoice? = nil
    ) {
        self.instructions = instructions
        self.tools = tools
        self.toolChoice = toolChoice
    }
}

/// High-level turn runner for OpenAI Realtime sessions.
public actor OpenAIRealtimeTurnRunner: AgentTurnRunner {
    public let client: OpenAIRealtimeWebSocketClient
    public let configuration: OpenAIRealtimeTurnRunnerConfiguration
    public let executor: ToolExecutor?
    public let middleware: AgentMiddlewareStack
    private var isConnected = false

    /// Creates a one-turn Realtime runner.
    /// - Parameters:
    ///   - client: Realtime WebSocket client used for session communication.
    ///   - configuration: Runner configuration describing instructions and tool behavior.
    ///   - executor: Optional tool executor used when the model emits tool calls.
    public init(
        client: OpenAIRealtimeWebSocketClient,
        configuration: OpenAIRealtimeTurnRunnerConfiguration = .init(),
        executor: ToolExecutor? = nil,
        middleware: AgentMiddlewareStack = AgentMiddlewareStack()
    ) {
        self.client = client
        self.configuration = configuration
        self.executor = executor
        self.middleware = middleware
    }

    /// Runs one Realtime turn against a connected session.
    /// - Parameter input: Provider-neutral input messages for the turn.
    /// - Returns: A stream of provider-neutral events emitted for the turn.
    /// - Throws: An error if the supplied messages cannot be represented by the Realtime protocol.
    public nonisolated func runTurn(
        input: [AgentMessage]
    ) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let requestContext = try await self.prepareRequestContext(input: input)
                    try await self.ensureConnected()
                    try await self.configureSessionIfNeeded(tools: requestContext.tools)
                    for message in requestContext.input {
                        try await self.send(message: message)
                    }
                    try await self.client.createResponse()

                    let events = try await self.client.receiveUntilTurnFinished(using: self.executor)
                    for event in try await self.processResponseEvents(
                        events,
                        model: requestContext.model
                    ) {
                        continuation.yield(event)
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
}

private extension OpenAIRealtimeTurnRunner {
    func prepareRequestContext(
        input: [AgentMessage]
    ) async throws -> AgentModelRequestContext {
        let context = try await middleware.prepareModelRequest(
            AgentModelRequestContext(
                provider: .openAI,
                model: client.configuration.model,
                input: input,
                tools: configuration.tools,
                stream: true,
                metadata: [
                    "instructions": configuration.instructions ?? "",
                    "toolChoice": configuration.toolChoice.map(String.init(describing:)) ?? "",
                ]
            )
        )
        await middleware.recordAuditEvent(.modelRequestStarted(.init(context: context)))
        return context
    }

    func ensureConnected() async throws {
        guard !isConnected else { return }
        try await client.connect()
        isConnected = true
    }

    func configureSessionIfNeeded(tools: [ToolDescriptor]) async throws {
        let shouldUpdateSession =
            configuration.instructions != nil ||
            !tools.isEmpty ||
            configuration.toolChoice != nil

        guard shouldUpdateSession else {
            return
        }

        try await client.updateSession(
            .init(
                instructions: configuration.instructions,
                tools: tools,
                toolChoice: configuration.toolChoice
            )
        )
    }

    func send(message: AgentMessage) async throws {
        switch message.role {
        case .user:
            try await client.sendUserMessage(message)
        case .system, .developer, .assistant, .tool:
            throw AgentDecodingError.requestEncoding(
                provider: .openAI,
                description: "unsupported realtime message role: \(message.role.rawValue)"
            )
        }
    }

    func processResponseEvents(
        _ events: [AgentStreamEvent],
        model: String
    ) async throws -> [AgentStreamEvent] {
        var toolCalls: [AgentToolCall] = []
        var processedEvents: [AgentStreamEvent] = []

        for event in events {
            switch event {
            case .toolCall(let toolCall):
                toolCalls.append(toolCall)
                processedEvents.append(.toolCall(toolCall))

            case .messagesCompleted(let messages):
                let context = try await middleware.processModelResponse(
                    AgentModelResponseContext(
                        provider: .openAI,
                        model: model,
                        messages: messages,
                        toolCalls: toolCalls
                    )
                )
                await middleware.recordAuditEvent(.modelResponseCompleted(.init(context: context)))
                if !context.messages.isEmpty {
                    processedEvents.append(.messagesCompleted(context.messages))
                }
                toolCalls.removeAll()

            default:
                processedEvents.append(event)
            }
        }

        return processedEvents
    }
}
