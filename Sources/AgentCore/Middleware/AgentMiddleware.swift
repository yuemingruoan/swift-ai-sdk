import Foundation

/// Provider-neutral model request context exposed to request middleware.
public struct AgentModelRequestContext: Equatable, Sendable {
    public var provider: AgentProviderID
    public var model: String
    public var input: [AgentMessage]
    public var tools: [ToolDescriptor]
    public var stream: Bool
    public var metadata: [String: String]

    /// Creates a provider-neutral request context for runtime middleware.
    public init(
        provider: AgentProviderID,
        model: String,
        input: [AgentMessage],
        tools: [ToolDescriptor],
        stream: Bool,
        metadata: [String: String] = [:]
    ) {
        self.provider = provider
        self.model = model
        self.input = input
        self.tools = tools
        self.stream = stream
        self.metadata = metadata
    }
}

/// Provider-neutral model response context exposed to response middleware.
public struct AgentModelResponseContext: Equatable, Sendable {
    public var provider: AgentProviderID
    public var model: String
    public var messages: [AgentMessage]
    public var toolCalls: [AgentToolCall]
    public var metadata: [String: String]

    /// Creates a provider-neutral response context for runtime middleware.
    public init(
        provider: AgentProviderID,
        model: String,
        messages: [AgentMessage],
        toolCalls: [AgentToolCall],
        metadata: [String: String] = [:]
    ) {
        self.provider = provider
        self.model = model
        self.messages = messages
        self.toolCalls = toolCalls
        self.metadata = metadata
    }
}

/// Tool invocation context exposed to authorization and audit middleware.
public struct AgentToolInvocationContext: Equatable, Sendable {
    public var descriptor: ToolDescriptor
    public var invocation: ToolInvocation
    public var provider: AgentProviderID?
    public var model: String?
    public var metadata: [String: String]

    /// Creates tool invocation context for middleware decisions and audit records.
    public init(
        descriptor: ToolDescriptor,
        invocation: ToolInvocation,
        provider: AgentProviderID? = nil,
        model: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.descriptor = descriptor
        self.invocation = invocation
        self.provider = provider
        self.model = model
        self.metadata = metadata
    }
}

/// Authorization outcome returned by tool-authorization middleware.
public enum AgentToolAuthorizationDecision: Equatable, Sendable {
    case allow
    case deny(reason: String?)
}

/// Reason recorded when message redaction middleware rewrites completed messages.
public enum AgentMessageRedactionReason: String, Codable, Equatable, Sendable {
    case messagesCompleted
    case turnCompleted
    case persistedTurn
    case stateUpdated
}

/// Structured audit event for a model request entering the runtime layer.
public struct AgentAuditModelRequestEvent: Equatable, Sendable {
    public var context: AgentModelRequestContext

    /// Creates a structured audit event for a model request.
    public init(context: AgentModelRequestContext) {
        self.context = context
    }
}

/// Structured audit event for a model response leaving the runtime layer.
public struct AgentAuditModelResponseEvent: Equatable, Sendable {
    public var context: AgentModelResponseContext

    /// Creates a structured audit event for a model response.
    public init(context: AgentModelResponseContext) {
        self.context = context
    }
}

/// Structured audit event for a tool authorization decision.
public struct AgentAuditToolDecisionEvent: Equatable, Sendable {
    public var context: AgentToolInvocationContext
    public var reason: String?

    /// Creates a structured audit event for an allow or deny tool decision.
    public init(context: AgentToolInvocationContext, reason: String? = nil) {
        self.context = context
        self.reason = reason
    }
}

/// Structured audit event emitted after message redaction runs.
public struct AgentAuditMessagesRedactedEvent: Equatable, Sendable {
    public var reason: AgentMessageRedactionReason
    public var originalCount: Int
    public var redactedCount: Int

    /// Creates a structured audit event for message redaction.
    public init(
        reason: AgentMessageRedactionReason,
        originalCount: Int,
        redactedCount: Int
    ) {
        self.reason = reason
        self.originalCount = originalCount
        self.redactedCount = redactedCount
    }
}

/// Structured audit events emitted by the runtime middleware stack.
public enum AgentAuditEvent: Equatable, Sendable {
    case modelRequestStarted(AgentAuditModelRequestEvent)
    case modelResponseCompleted(AgentAuditModelResponseEvent)
    case toolAllowed(AgentAuditToolDecisionEvent)
    case toolDenied(AgentAuditToolDecisionEvent)
    case messagesRedacted(AgentAuditMessagesRedactedEvent)
}

/// Middleware that can rewrite a provider-neutral request before execution.
public protocol AgentModelRequestMiddleware: Sendable {
    func prepare(_ context: AgentModelRequestContext) async throws -> AgentModelRequestContext
}

public extension AgentModelRequestMiddleware {
    /// Default no-op implementation for request middleware.
    func prepare(_ context: AgentModelRequestContext) async throws -> AgentModelRequestContext {
        context
    }
}

/// Middleware that can rewrite a provider-neutral response after projection.
public protocol AgentModelResponseMiddleware: Sendable {
    func process(_ context: AgentModelResponseContext) async throws -> AgentModelResponseContext
}

public extension AgentModelResponseMiddleware {
    /// Default no-op implementation for response middleware.
    func process(_ context: AgentModelResponseContext) async throws -> AgentModelResponseContext {
        context
    }
}

/// Middleware that can allow or deny a tool call before execution.
public protocol AgentToolAuthorizationMiddleware: Sendable {
    func authorize(_ context: AgentToolInvocationContext) async throws -> AgentToolAuthorizationDecision
}

public extension AgentToolAuthorizationMiddleware {
    /// Default implementation that allows the tool call.
    func authorize(_ context: AgentToolInvocationContext) async throws -> AgentToolAuthorizationDecision {
        .allow
    }
}

/// Middleware that can redact completed messages before they are emitted or persisted.
public protocol AgentMessageRedactionMiddleware: Sendable {
    func redact(
        _ messages: [AgentMessage],
        reason: AgentMessageRedactionReason
    ) async throws -> [AgentMessage]
}

public extension AgentMessageRedactionMiddleware {
    /// Default no-op implementation for redaction middleware.
    func redact(
        _ messages: [AgentMessage],
        reason: AgentMessageRedactionReason
    ) async throws -> [AgentMessage] {
        messages
    }
}

/// Middleware that records structured runtime audit events.
public protocol AgentAuditMiddleware: Sendable {
    func record(_ event: AgentAuditEvent) async
}

public extension AgentAuditMiddleware {
    /// Default no-op implementation for audit middleware.
    func record(_ event: AgentAuditEvent) async {}
}

/// Shared runtime container for middleware registration and invocation order.
public actor AgentMiddlewareStack {
    private var modelRequest: [any AgentModelRequestMiddleware]
    private var modelResponse: [any AgentModelResponseMiddleware]
    private var toolAuthorization: [any AgentToolAuthorizationMiddleware]
    private var messageRedaction: [any AgentMessageRedactionMiddleware]
    private var audit: [any AgentAuditMiddleware]

    /// Creates a middleware stack with explicit middleware ordering per category.
    public init(
        modelRequest: [any AgentModelRequestMiddleware] = [],
        modelResponse: [any AgentModelResponseMiddleware] = [],
        toolAuthorization: [any AgentToolAuthorizationMiddleware] = [],
        messageRedaction: [any AgentMessageRedactionMiddleware] = [],
        audit: [any AgentAuditMiddleware] = []
    ) {
        self.modelRequest = modelRequest
        self.modelResponse = modelResponse
        self.toolAuthorization = toolAuthorization
        self.messageRedaction = messageRedaction
        self.audit = audit
    }

    /// Appends request middleware to the stack.
    public func register(_ middleware: any AgentModelRequestMiddleware) {
        modelRequest.append(middleware)
    }

    /// Appends response middleware to the stack.
    public func register(_ middleware: any AgentModelResponseMiddleware) {
        modelResponse.append(middleware)
    }

    /// Appends tool-authorization middleware to the stack.
    public func register(_ middleware: any AgentToolAuthorizationMiddleware) {
        toolAuthorization.append(middleware)
    }

    /// Appends message-redaction middleware to the stack.
    public func register(_ middleware: any AgentMessageRedactionMiddleware) {
        messageRedaction.append(middleware)
    }

    /// Appends audit middleware to the stack.
    public func register(_ middleware: any AgentAuditMiddleware) {
        audit.append(middleware)
    }

    /// Runs request middleware in registration order.
    public func prepareModelRequest(
        _ context: AgentModelRequestContext
    ) async throws -> AgentModelRequestContext {
        var current = context
        for middleware in modelRequest {
            current = try await middleware.prepare(current)
        }
        return current
    }

    /// Runs response middleware in registration order.
    public func processModelResponse(
        _ context: AgentModelResponseContext
    ) async throws -> AgentModelResponseContext {
        var current = context
        for middleware in modelResponse {
            current = try await middleware.process(current)
        }
        return current
    }

    /// Runs tool-authorization middleware until one denies or all allow.
    public func authorizeToolInvocation(
        _ context: AgentToolInvocationContext
    ) async throws -> AgentToolAuthorizationDecision {
        for middleware in toolAuthorization {
            let decision = try await middleware.authorize(context)
            if case .deny = decision {
                return decision
            }
        }
        return .allow
    }

    /// Runs message-redaction middleware in registration order.
    public func redactMessages(
        _ messages: [AgentMessage],
        reason: AgentMessageRedactionReason
    ) async throws -> [AgentMessage] {
        var current = messages
        for middleware in messageRedaction {
            current = try await middleware.redact(current, reason: reason)
        }
        return current
    }

    /// Records a structured audit event with every registered audit middleware.
    public func recordAuditEvent(_ event: AgentAuditEvent) async {
        for middleware in audit {
            await middleware.record(event)
        }
    }
}
