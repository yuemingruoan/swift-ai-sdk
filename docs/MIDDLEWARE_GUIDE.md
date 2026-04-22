# Runtime Middleware Guide

This guide documents the current runtime middleware surface in `swift-ai-sdk`.
It focuses on what exists today, where the middleware stack is evaluated, and
how hosts can use it without confusing it with the lower-level transport layer.

## Design Boundaries

`AgentMiddlewareStack` is a runtime-layer construct. It sits above raw HTTP/SSE
transports and above provider-specific request builders.

The current split is intentional:

- middleware governs model request/response interception, tool authorization,
  message redaction, and audit recording
- `AgentHTTPTransportConfiguration` governs request-level HTTP knobs such as
  timeout, retry, headers, user agent, and request ID
- `ToolExecutorHook` remains observational and is not replaced by middleware

If no middleware is installed, the runtime keeps the existing zero-extra-behavior
path.

## Available Middleware Protocols

| Protocol | Purpose | Current level |
| --- | --- | --- |
| `AgentModelRequestMiddleware` | Inspect or rewrite provider-neutral request context before dispatch | High-level runtime |
| `AgentModelResponseMiddleware` | Inspect or rewrite provider-neutral completed response context | High-level runtime |
| `AgentToolAuthorizationMiddleware` | Allow or deny tool execution before any local executable or remote transport runs | Tool execution |
| `AgentMessageRedactionMiddleware` | Rewrite completed messages before state update or persistence write | Session/persistence |
| `AgentAuditMiddleware` | Observe structured audit events from request, response, authorization, and redaction paths | Runtime-wide |

The stack itself is `AgentMiddlewareStack`.

## Current Injection Points

The shared middleware stack is currently consumed by:

- `ToolExecutor`
- `AgentSessionRunner`
- `RecordingAgentTurnRunner`
- `OpenAIResponsesTurnRunner`
- `OpenAIRealtimeTurnRunner`
- `AnthropicTurnRunner`

This means one stack can govern request/response handling, tool allow/deny,
session-state updates, and persistence emission across both providers.

## Current Audit Events

Audit middleware currently receives structured `AgentAuditEvent` values:

- `modelRequestStarted`
- `modelResponseCompleted`
- `toolAllowed`
- `toolDenied`
- `messagesRedacted`

The public payloads are typed and provider-neutral. The audit path is intended
for host logging and decision tracing, not for free-form console text.

## Tool Authorization Behavior

Tool authorization is evaluated inside `ToolExecutor` before the executor calls
either:

- a local executable, or
- a remote transport

The authorization result is one of two values:

- `.allow`
- `.deny(reason: String?)`

When denied:

- the underlying tool is not executed
- the runtime records a `toolDenied` audit event
- the call fails with `AgentRuntimeError.toolCallDenied`

## Message Redaction Behavior

The current redaction scope is intentionally narrow:

- it applies to complete messages
- it does not rewrite streaming `textDelta` fragments
- it runs before `AgentSessionRunner` emits `stateUpdated`
- it runs before `RecordingAgentTurnRunner` persists or re-emits completed turns

This keeps the first middleware release predictable and avoids mixing partial
stream mutation with persistence policy.

## Anthropic Streaming And Middleware

Anthropic streaming now works with the same high-level middleware stack used by
the non-streaming path.

The relevant pieces are:

- `URLSessionAnthropicMessagesStreamingTransport`
- `AnthropicMessageStreamEvent`
- `AnthropicMessagesClient(..., streamingTransport: ...)`
- `AnthropicTurnRunnerConfiguration(stream: true)`

The turn runner still projects into the existing `AgentStreamEvent` surface:

- text fragments become `.textDelta`
- completed tool uses become `.toolCall`
- completed assistant messages become `.messagesCompleted`

`AgentModelResponseMiddleware` runs on the completed projected message context,
not on raw streaming deltas.

## Minimal Example

```swift
import AnthropicAgentRuntime
import AnthropicMessagesAPI

let middleware = AgentMiddlewareStack(
    toolAuthorization: [
        HostToolPolicy(deniedToolName: "dangerous_tool")
    ],
    audit: [
        HostAuditSink()
    ]
)

let client = AnthropicMessagesClient(
    transport: URLSessionAnthropicMessagesTransport(
        configuration: .init(apiKey: anthropicKey)
    ),
    streamingTransport: URLSessionAnthropicMessagesStreamingTransport(
        configuration: .init(apiKey: anthropicKey)
    )
)

let runner = AnthropicTurnRunner(
    client: client,
    configuration: .init(
        model: "claude-sonnet-4-20250514",
        maxTokens: 1024,
        tools: [tool],
        stream: true
    ),
    executor: executor,
    middleware: middleware
)
```

The package also ships a runnable smoke path:

```bash
ANTHROPIC_STREAM=true EXAMPLE_PRINT_AUDIT=true swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
ANTHROPIC_STREAM=true EXAMPLE_DENY_TOOL=lookup_weather swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
```

## Deliberate Limits

This guide does not promise:

- transport-level URLRequest rewriting middleware
- mutation of partial stream deltas
- provider-specific policy surfaces outside the shared SDK taxonomy
- a full observability product surface beyond the current audit events
