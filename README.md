# swift-ai-sdk

Swift-first AI runtime infrastructure for Apple-platform hosts, with a provider-neutral core and OpenAI implementations layered on top.

The current repository focuses on four things:

- `AgentCore`: provider-neutral message, streaming, tool, and runner primitives
- `AgentOpenAI`: OpenAI Responses, SSE streaming, and Realtime WebSocket integrations
- `AgentPersistence`: persistence protocols, an in-memory store, and a recording runner wrapper
- `AgentMacros`: `@Tool` macro support for emitting `ToolDescriptor` metadata

The SDK is designed to be SwiftData-friendly without importing or depending on `SwiftData`. Persistence stays behind protocols so hosts can provide a SwiftData-backed adapter in their own target without making the SDK Apple-framework-bound.

## Status

This repository is currently a working v1 infrastructure baseline, not a finished public SDK. The implemented surface is enough to:

- run one-turn OpenAI Responses requests
- stream OpenAI Responses over SSE
- run one-turn OpenAI Realtime WebSocket sessions
- register local or remote tools through one contract
- resolve OpenAI tool calls automatically in both Responses and Realtime flows
- persist completed turns through protocol-based stores

What is intentionally not present yet:

- Anthropic support
- a built-in SwiftData adapter target
- a provider-neutral multi-turn session runtime
- richer tool metadata and middleware hooks

## Package Layout

```text
Sources/
  AgentCore/
  AgentOpenAI/
  AgentPersistence/
  AgentMacros/
  AgentMacrosPlugin/

Examples/
  OpenAIResponsesExample/

Tests/
  AgentCoreTests/
  AgentOpenAITests/
  AgentPersistenceTests/
  AgentMacrosTests/
```

## Products

Defined in [Package.swift](Package.swift):

- `AgentCore`
- `AgentOpenAI`
- `AgentPersistence`
- `AgentMacros`
- `OpenAIResponsesExample`

Supported platforms:

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+
- visionOS 1+

## Core Concepts

### Messages and Events

`AgentCore` exposes the provider-neutral runtime surface:

- `AgentMessage`
- `MessagePart`
- `AgentStreamEvent`
- `AgentTurn`
- `AgentSession`
- `AgentTurnRunner`

The important event cases today are:

- `.textDelta(String)`
- `.toolCall(AgentToolCall)`
- `.messagesCompleted([AgentMessage])`
- `.turnCompleted(AgentTurn)`

### Tools

Tools are described with `ToolDescriptor` and executed through `ToolExecutor`.

The same invocation model covers:

- local tools via `LocalToolExecutable`
- remote tools via `RemoteToolTransport`

That keeps provider integrations focused on schema conversion and tool-loop control, not on host-specific execution details.

### Persistence

Persistence stays protocol-based:

- `AgentSessionStore`
- `AgentTurnStore`

Built-in implementations:

- `InMemoryAgentStore`
- `RecordingAgentTurnRunner`

`RecordingAgentTurnRunner` wraps any `AgentTurnRunner`, persists completed turns, and emits a final `.turnCompleted(...)` event using the persisted turn.

## OpenAI Surface

### Responses

Implemented pieces:

- `OpenAIResponseRequest`
- `OpenAIResponsesClient`
- `URLSessionOpenAIResponsesTransport`
- `URLSessionOpenAIResponsesStreamingTransport`
- `OpenAIResponsesTurnRunner`

Supported capabilities:

- structured request building
- tool descriptor to OpenAI function-tool conversion
- non-streaming and streaming projection into `AgentStreamEvent`
- automatic tool execution loop for Responses

### Realtime

Implemented pieces:

- `OpenAIRealtimeWebSocketClient`
- `OpenAIRealtimeRequestBuilder`
- `OpenAIRealtimeSessionUpdateEvent`
- `OpenAIRealtimeConversationItemCreateEvent`
- `OpenAIRealtimeResponseCreateEvent`
- `OpenAIRealtimeTurnRunner`

Supported capabilities:

- typed session updates
- user message sending
- structured function call output sending
- automatic tool execution loop for Realtime
- projection back into `AgentStreamEvent`

## Example

The repository includes one executable example:

- `OpenAIResponsesExample`

Build it:

```bash
swift build --target OpenAIResponsesExample
```

Run it:

```bash
OPENAI_API_KEY=sk-... swift run OpenAIResponsesExample "Write one sentence about Swift concurrency."
```

Optional environment variables:

- `OPENAI_API_KEY`
- `OPENAI_MODEL` with default `gpt-5.4`

## Minimal Usage

### One-turn OpenAI Responses runner

```swift
import AgentCore
import AgentOpenAI

let transport = URLSessionOpenAIResponsesTransport(
    configuration: .init(apiKey: apiKey)
)
let streamingTransport = URLSessionOpenAIResponsesStreamingTransport(
    configuration: .init(apiKey: apiKey)
)
let client = OpenAIResponsesClient(
    transport: transport,
    streamingTransport: streamingTransport
)

let runner = OpenAIResponsesTurnRunner(
    client: client,
    configuration: .init(
        model: "gpt-5.4",
        stream: true
    )
)

for try await event in try runner.runTurn(input: [.userText("hello")]) {
    print(event)
}
```

### Recording completed turns

```swift
import AgentCore
import AgentOpenAI
import AgentPersistence

let store = InMemoryAgentStore()
let recordedRunner = RecordingAgentTurnRunner(
    base: runner,
    session: .init(id: "session-1"),
    sessionStore: store,
    turnStore: store
)
```

## Testing

Run the full suite:

```bash
swift test
```

Key test groups:

- `AgentCoreTests`
- `AgentOpenAITests`
- `AgentPersistenceTests`
- `AgentMacrosTests`

## Design Constraints

The current implementation follows these constraints:

- Swift-first value types are the source of truth
- provider-specific request models are adapters on top of core types
- persistence remains protocol-driven and cross-platform
- SwiftData support should be added as an adapter target, not as a hard dependency
- local and remote tools share one invocation contract from day one

## Next Work

The ordered functional roadmap lives in [SDK_IMPROVEMENT_PLAN.md](SDK_IMPROVEMENT_PLAN.md).
