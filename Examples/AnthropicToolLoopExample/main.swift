import AnthropicAgentRuntime
import AnthropicMessagesAPI
import ExampleSupport
import Foundation

@main
enum AnthropicToolLoopExample {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("AnthropicToolLoopExample failed: \(String(describing: error))\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let apiKey = ExampleEnvironment.require(
            "ANTHROPIC_API_KEY",
            help: "Set ANTHROPIC_API_KEY before running AnthropicToolLoopExample."
        )
        let model = ExampleEnvironment.value(
            "ANTHROPIC_MODEL",
            default: "claude-sonnet-4-20250514"
        )
        let baseURL = ExampleEnvironment.url(
            "ANTHROPIC_BASE_URL",
            default: "https://api.anthropic.com/v1"
        )
        let version = ExampleEnvironment.value(
            "ANTHROPIC_VERSION",
            default: "2023-06-01"
        )
        let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
        let input = prompt.isEmpty
            ? "What is the weather in Paris? Use the tool."
            : prompt
        let stream = ExampleEnvironment.value(
            "ANTHROPIC_STREAM",
            default: "false"
        ).lowercased() == "true"
        let deniedTool = ExampleEnvironment.value("EXAMPLE_DENY_TOOL", default: "")
        let responsePrefix = ExampleEnvironment.value("EXAMPLE_RESPONSE_PREFIX", default: "")
        let printAudit = ExampleEnvironment.value(
            "EXAMPLE_PRINT_AUDIT",
            default: "false"
        ).lowercased() == "true"
        let includeThinking = ExampleEnvironment.value(
            "ANTHROPIC_INCLUDE_THINKING",
            default: "false"
        ).lowercased() == "true"

        let tool = demoWeatherToolDescriptor()
        let registry = ToolRegistry()
        try await registry.register(tool)
        let middleware = AgentMiddlewareStack(
            modelResponse: responsePrefix.isEmpty ? [] : [
                ExampleResponsePrefixMiddleware(prefix: responsePrefix)
            ],
            toolAuthorization: deniedTool.isEmpty ? [] : [
                ExampleToolAuthorizationMiddleware(deniedToolName: deniedTool)
            ],
            audit: printAudit ? [ExampleAuditMiddleware()] : []
        )
        let executor = ToolExecutor(registry: registry, middleware: middleware)
        await executor.register(DemoWeatherTransport())

        let transport = URLSessionAnthropicMessagesTransport(
            configuration: .init(
                apiKey: apiKey,
                baseURL: baseURL,
                version: version
            )
        )
        let streamingTransport = URLSessionAnthropicMessagesStreamingTransport(
            configuration: .init(
                apiKey: apiKey,
                baseURL: baseURL,
                version: version
            )
        )
        let client = AnthropicMessagesClient(
            transport: transport,
            streamingTransport: streamingTransport
        )
        let runner = AnthropicTurnRunner(
            client: client,
            configuration: .init(
                model: model,
                maxTokens: 1024,
                tools: [tool],
                stream: stream,
                projectionOptions: includeThinking ? .preserveThinking : .omitThinking
            ),
            executor: executor,
            middleware: middleware
        )

        ExampleEventPrinter.printDivider("Anthropic Tool Loop")
        for try await event in try runner.runTurn(input: [.userText(input)]) {
            ExampleEventPrinter.printEvent(event)
        }
    }
}

private struct ExampleResponsePrefixMiddleware: AgentModelResponseMiddleware {
    let prefix: String?

    func process(_ context: AgentModelResponseContext) async throws -> AgentModelResponseContext {
        guard let prefix, !prefix.isEmpty else {
            return context
        }

        return AgentModelResponseContext(
            provider: context.provider,
            model: context.model,
            messages: context.messages.map { message in
                AgentMessage(
                    role: message.role,
                    parts: message.parts.map { part in
                        switch part {
                        case .text(let text):
                            return .text(prefix + text)
                        case .image:
                            return part
                        }
                    }
                )
            },
            toolCalls: context.toolCalls,
            metadata: context.metadata
        )
    }
}

private struct ExampleToolAuthorizationMiddleware: AgentToolAuthorizationMiddleware {
    let deniedToolName: String?

    func authorize(_ context: AgentToolInvocationContext) async throws -> AgentToolAuthorizationDecision {
        guard
            let deniedToolName,
            !deniedToolName.isEmpty,
            context.descriptor.name == deniedToolName
        else {
            return .allow
        }

        return .deny(reason: "Example policy denied tool: \(deniedToolName)")
    }
}

private actor ExampleAuditMiddleware: AgentAuditMiddleware {
    func record(_ event: AgentAuditEvent) async {
        switch event {
        case .modelRequestStarted(let event):
            print("[audit] modelRequestStarted provider=\(event.context.provider.rawValue) model=\(event.context.model) stream=\(event.context.stream)")
        case .modelResponseCompleted(let event):
            print("[audit] modelResponseCompleted provider=\(event.context.provider.rawValue) messages=\(event.context.messages.count) toolCalls=\(event.context.toolCalls.count)")
        case .toolAllowed(let event):
            print("[audit] toolAllowed name=\(event.context.descriptor.name)")
        case .toolDenied(let event):
            print("[audit] toolDenied name=\(event.context.descriptor.name) reason=\(event.reason ?? "unspecified")")
        case .messagesRedacted(let event):
            print("[audit] messagesRedacted reason=\(event.reason.rawValue) original=\(event.originalCount) redacted=\(event.redactedCount)")
        }
    }
}
