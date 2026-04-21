import AgentCore
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

    /// Creates a one-turn Responses runner.
    /// - Parameters:
    ///   - client: High-level Responses client used for request execution.
    ///   - configuration: Runner configuration describing model and tool behavior.
    ///   - executor: Optional tool executor used when the model emits tool calls.
    public init(
        client: OpenAIResponsesClient,
        configuration: OpenAIResponsesTurnRunnerConfiguration,
        executor: ToolExecutor? = nil
    ) {
        self.client = client
        self.configuration = configuration
        self.executor = executor
    }

    /// Runs one Responses turn and yields provider-neutral events.
    /// - Parameter input: Provider-neutral input messages for the turn.
    /// - Returns: A stream of provider-neutral events emitted for the turn.
    /// - Throws: An error if the request cannot be constructed from the supplied messages.
    public func runTurn(input: [AgentMessage]) throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let request = try OpenAIResponseRequest(
            model: configuration.model,
            messages: input,
            previousResponseID: configuration.previousResponseID,
            stream: configuration.stream,
            tools: configuration.tools,
            toolChoice: configuration.toolChoice
        )

        if let executor {
            return client.projectedResponseEvents(
                request,
                using: executor,
                stream: configuration.stream
            )
        }

        return client.projectedResponseEvents(
            request,
            stream: configuration.stream
        )
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

/// Errors thrown when provider-neutral messages cannot be sent through Realtime.
public enum OpenAIRealtimeTurnRunnerError: Error, Equatable, Sendable {
    case unsupportedMessageRole(String)
    case unsupportedMessagePart(String)
}

/// High-level turn runner for OpenAI Realtime sessions.
public actor OpenAIRealtimeTurnRunner: AgentTurnRunner {
    public let client: OpenAIRealtimeWebSocketClient
    public let configuration: OpenAIRealtimeTurnRunnerConfiguration
    public let executor: ToolExecutor?
    private var isConnected = false

    /// Creates a one-turn Realtime runner.
    /// - Parameters:
    ///   - client: Realtime WebSocket client used for session communication.
    ///   - configuration: Runner configuration describing instructions and tool behavior.
    ///   - executor: Optional tool executor used when the model emits tool calls.
    public init(
        client: OpenAIRealtimeWebSocketClient,
        configuration: OpenAIRealtimeTurnRunnerConfiguration = .init(),
        executor: ToolExecutor? = nil
    ) {
        self.client = client
        self.configuration = configuration
        self.executor = executor
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
                    try await self.ensureConnected()
                    try await self.configureSessionIfNeeded()
                    for message in input {
                        try await self.send(message: message)
                    }
                    try await self.client.createResponse()

                    let events = try await self.client.receiveUntilTurnFinished(using: self.executor)
                    for event in events {
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
    func ensureConnected() async throws {
        guard !isConnected else { return }
        try await client.connect()
        isConnected = true
    }

    func configureSessionIfNeeded() async throws {
        let shouldUpdateSession =
            configuration.instructions != nil ||
            !configuration.tools.isEmpty ||
            configuration.toolChoice != nil

        guard shouldUpdateSession else {
            return
        }

        try await client.updateSession(
            .init(
                instructions: configuration.instructions,
                tools: configuration.tools,
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
}
