import Foundation

/// Errors thrown while resolving and invoking registered tools.
public enum ToolExecutorError: Error, Equatable, Sendable {
    case unknownTool(name: String)
    case missingLocalExecutable(name: String)
    case missingRemoteTransport(id: String)
    case invalidRemoteDescriptor(name: String)
}

/// Resolves tool descriptors and dispatches invocations to local or remote implementations.
public actor ToolExecutor {
    private let registry: ToolRegistry
    private let middleware: AgentMiddlewareStack
    private var hooks: [any ToolExecutorHook]
    private var localExecutables: [String: any LocalToolExecutable] = [:]
    private var remoteTransports: [String: any RemoteToolTransport] = [:]

    /// Creates a tool executor with an optional preconfigured registry and hooks.
    /// - Parameters:
    ///   - registry: Registry used to resolve descriptors by tool name.
    ///   - middleware: Shared middleware stack used for authorization and audit.
    ///   - hooks: Observational hooks notified before and after invocation.
    public init(
        registry: ToolRegistry = ToolRegistry(),
        middleware: AgentMiddlewareStack = AgentMiddlewareStack(),
        hooks: [any ToolExecutorHook] = []
    ) {
        self.registry = registry
        self.middleware = middleware
        self.hooks = hooks
    }

    /// Registers a local executable and its descriptor.
    /// - Parameter executable: Local tool implementation to register.
    /// - Throws: An error if the executable's descriptor cannot be registered in the tool registry.
    public func register(_ executable: any LocalToolExecutable) async throws {
        try await registry.register(executable.descriptor)
        localExecutables[executable.descriptor.name] = executable
    }

    /// Registers a remote transport by its transport identifier.
    /// - Parameter transport: Remote transport capable of executing one or more remote tools.
    public func register(_ transport: any RemoteToolTransport) {
        remoteTransports[transport.transportID] = transport
    }

    /// Registers an observational hook that will receive invocation callbacks.
    /// - Parameter hook: Hook notified for future tool invocations.
    public func register(_ hook: any ToolExecutorHook) {
        hooks.append(hook)
    }

    /// Invokes a tool through the matching local executable or remote transport.
    /// - Parameter invocation: Tool name plus encoded argument payload.
    /// - Returns: The provider-neutral result returned by the matched implementation.
    /// - Throws: An error if the descriptor is unknown, the backing implementation is missing, or the invocation itself fails.
    public func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        guard let descriptor = await registry.descriptor(named: invocation.toolName) else {
            throw ToolExecutorError.unknownTool(name: invocation.toolName)
        }

        let authorizationContext = AgentToolInvocationContext(
            descriptor: descriptor,
            invocation: invocation
        )
        let decision = try await middleware.authorizeToolInvocation(authorizationContext)
        switch decision {
        case .allow:
            await middleware.recordAuditEvent(
                .toolAllowed(.init(context: authorizationContext))
            )
        case .deny(let reason):
            await middleware.recordAuditEvent(
                .toolDenied(.init(context: authorizationContext, reason: reason))
            )
            throw AgentRuntimeError.toolCallDenied(
                toolName: descriptor.name,
                reason: reason
            )
        }

        for hook in hooks {
            await hook.willInvoke(descriptor: descriptor, invocation: invocation)
        }

        do {
            let result: ToolResult

            switch descriptor.executionKind {
            case .local:
                guard let executable = localExecutables[descriptor.name] else {
                    throw ToolExecutorError.missingLocalExecutable(name: descriptor.name)
                }

                result = try await executable.invoke(invocation)

            case .remote:
                guard let transportID = descriptor.remoteTransportID else {
                    throw ToolExecutorError.invalidRemoteDescriptor(name: descriptor.name)
                }
                guard let transport = remoteTransports[transportID] else {
                    throw ToolExecutorError.missingRemoteTransport(id: transportID)
                }

                result = try await transport.invoke(invocation)
            }

            for hook in hooks {
                await hook.didInvoke(
                    descriptor: descriptor,
                    invocation: invocation,
                    result: result
                )
            }

            return result
        } catch {
            let failure = ToolExecutorInvocationFailure(error: error)
            for hook in hooks {
                await hook.didFail(
                    descriptor: descriptor,
                    invocation: invocation,
                    failure: failure
                )
            }
            throw error
        }
    }
}
