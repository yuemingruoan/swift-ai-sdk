import Foundation

public enum ToolExecutorError: Error, Equatable, Sendable {
    case unknownTool(name: String)
    case missingLocalExecutable(name: String)
    case missingRemoteTransport(id: String)
    case invalidRemoteDescriptor(name: String)
}

public actor ToolExecutor {
    private let registry: ToolRegistry
    private var hooks: [any ToolExecutorHook]
    private var localExecutables: [String: any LocalToolExecutable] = [:]
    private var remoteTransports: [String: any RemoteToolTransport] = [:]

    public init(
        registry: ToolRegistry = ToolRegistry(),
        hooks: [any ToolExecutorHook] = []
    ) {
        self.registry = registry
        self.hooks = hooks
    }

    public func register(_ executable: any LocalToolExecutable) async throws {
        try await registry.register(executable.descriptor)
        localExecutables[executable.descriptor.name] = executable
    }

    public func register(_ transport: any RemoteToolTransport) {
        remoteTransports[transport.transportID] = transport
    }

    public func register(_ hook: any ToolExecutorHook) {
        hooks.append(hook)
    }

    public func invoke(_ invocation: ToolInvocation) async throws -> ToolResult {
        guard let descriptor = await registry.descriptor(named: invocation.toolName) else {
            throw ToolExecutorError.unknownTool(name: invocation.toolName)
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
