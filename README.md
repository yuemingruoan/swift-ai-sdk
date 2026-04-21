# swift-ai-sdk

[English](README.md) | [简体中文](README.zh-CN.md)

Swift-first AI runtime infrastructure for Apple-platform hosts, with a provider-neutral core and provider-specific adapters layered on top.

The current repository focuses on seven things:

- `AgentCore`: provider-neutral message, streaming, tool, and runner primitives
- `AgentAnthropic`: Anthropic Messages request building, response projection, and one-turn runner support
- `AgentOpenAI`: OpenAI Responses, SSE streaming, and Realtime WebSocket integrations
- `AgentOpenAIAuth`: bearer-token providers, ChatGPT/Codex-compatible Responses transports, and third-party compatibility profiles
- `AgentOpenAIAuthApple`: Apple-only secure storage adapters layered on top of `AgentOpenAIAuth`
- `AgentPersistence`: persistence protocols, in-memory and file-backed stores, record mappers, and a recording runner wrapper
- `AgentMacros`: `@Tool` macro support for emitting `ToolDescriptor` metadata

The SDK is designed to be SwiftData-friendly without importing or depending on `SwiftData`. Persistence stays behind protocols so hosts can provide a SwiftData-backed adapter in their own target without making the SDK Apple-framework-bound.

## Status

This repository is currently a working infrastructure baseline, not a finished public SDK. The implemented surface is enough to:

- run one-turn OpenAI Responses requests
- stream OpenAI Responses over SSE
- run one-turn OpenAI Realtime WebSocket sessions
- run one-turn Anthropic Messages requests
- register local or remote tools through one contract
- resolve tool calls automatically in OpenAI Responses, OpenAI Realtime, and Anthropic Messages flows
- persist completed turns through protocol-based stores
- maintain provider-neutral multi-turn conversation state on top of turn runners
- observe tool execution through metadata-rich descriptors and executor hooks

What is intentionally not present yet:

- a built-in SwiftData adapter target
- Anthropic streaming or Realtime support
- policy/middleware interception beyond observational executor hooks
- a broader set of provider examples and host adapters

## Package Layout

```text
Sources/
  AgentCore/
  AgentAnthropic/
  AgentOpenAI/
  AgentOpenAIAuth/
  AgentOpenAIAuthApple/
  AgentPersistence/
  AgentMacros/
  AgentMacrosPlugin/

Examples/
  ExampleSupport/
  AppleHostExample/
  OpenAIResponsesExample/
  OpenAIToolLoopExample/
  AnthropicToolLoopExample/
  SessionRunnerExample/
  PersistenceExample/

Tests/
  AgentCoreTests/
  AgentAnthropicTests/
  AgentOpenAITests/
  AgentPersistenceTests/
  AgentMacrosTests/
```

## Products

Defined in [Package.swift](Package.swift):

- `AgentCore`
- `AgentAnthropic`
- `AgentOpenAI`
- `AgentOpenAIAuth`
- `AgentOpenAIAuthApple`
- `AgentPersistence`
- `AgentMacros`
- `OpenAIResponsesExample`
- `OpenAIToolLoopExample`
- `AnthropicToolLoopExample`
- `SessionRunnerExample`
- `PersistenceExample`

Supported platforms:

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+
- visionOS 1+

## Installation

The first public SwiftPM release is intended to be tagged as `0.1.0`. Until
that tag exists, depend on a branch or revision while the release-preparation
pull request is under review.

After `0.1.0` is published, add the package with a semantic-version requirement:

```swift
dependencies: [
    .package(
        url: "https://github.com/yuemingruoan/swift-ai-sdk.git",
        from: "0.1.0"
    )
]
```

If you need the unreleased baseline before the first tag lands, use a branch:

```swift
dependencies: [
    .package(
        url: "https://github.com/yuemingruoan/swift-ai-sdk.git",
        branch: "main"
    )
]
```

## Core Concepts

### Messages and Events

`AgentCore` exposes the provider-neutral runtime surface:

- `AgentMessage`
- `MessagePart`
- `AgentStreamEvent`
- `AgentConversationState`
- `AgentSessionStreamEvent`
- `AgentTurn`
- `AgentSession`
- `AgentTurnRunner`
- `AgentSessionRunner`

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

Descriptors can now carry:

- `description`
- `inputSchema`
- `outputSchema`

Tool execution can also be observed with `ToolExecutorHook`:

- `willInvoke`
- `didInvoke`
- `didFail`

That keeps provider integrations focused on schema conversion and tool-loop control, not on host-specific execution details.

### Persistence

Persistence stays protocol-based:

- `AgentSessionStore`
- `AgentTurnStore`

Built-in implementations:

- `InMemoryAgentStore`
- `FileAgentStore`
- `AgentSessionRecord`
- `AgentTurnRecord`
- `AgentPersistenceMapper`
- `RecordingAgentTurnRunner`

`RecordingAgentTurnRunner` wraps any `AgentTurnRunner`, persists completed turns, and emits a final `.turnCompleted(...)` event using the persisted turn.

`FileAgentStore` persists sessions and turns as JSON-backed records and reloads them on initialization, which gives hosts a lightweight cross-platform fallback store without introducing database or framework dependencies.

## Anthropic Surface

Implemented pieces:

- `AnthropicMessagesRequest`
- `AnthropicMessagesRequestBuilder`
- `AnthropicMessagesClient`
- `URLSessionAnthropicMessagesTransport`
- `AnthropicTurnRunner`

Supported capabilities:

- converting `AgentMessage` input into Anthropic Messages requests
- projecting Anthropic assistant text and `tool_use` blocks back into `AgentStreamEvent`
- automatic client-side tool execution loop for Messages
- sharing the same `ToolExecutor` contract used by other providers

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

### Auth And Compatibility

Implemented pieces:

- `OpenAIAuthTokens`
- `OpenAITokenProvider`
- `OpenAIExternalTokenProvider`
- `OpenAITokenStore`
- `OpenAITokenRefresher`
- `OpenAIManagedTokenProvider`
- `OpenAIOAuthMethod`
- `OpenAIOAuthSession`
- `OpenAIOAuthFlow`
- `OpenAIChatGPTOAuthConfiguration`
- `OpenAIChatGPTBrowserFlow`
- `OpenAIChatGPTDeviceCodeFlow`
- `OpenAIChatGPTTokenRefresher`
- `OpenAICompatibilityProfile`
- `OpenAIChatGPTRequestTransform`
- `OpenAIAuthenticatedResponsesRequestBuilder`
- `URLSessionOpenAIAuthenticatedResponsesTransport`
- `URLSessionOpenAIAuthenticatedResponsesStreamingTransport`

Apple adapter layer:

- `KeychainOpenAITokenStore` in `AgentOpenAIAuthApple`

Supported capabilities:

- caller-supplied bearer tokens through a provider contract
- store-backed token loading and refresh orchestration through `OpenAIManagedTokenProvider`
  while keeping storage itself behind a protocol boundary
- concrete ChatGPT/Codex browser-login URL generation plus callback code exchange
- concrete ChatGPT/Codex device-code login against `auth.openai.com`
- ChatGPT/Codex-compatible request shaping for `/backend-api/codex/responses`
- one-shot 401 refresh hooks through `OpenAITokenProvider.refreshTokens(...)`
- concrete OAuth refresh-token exchange against `auth.openai.com/oauth/token`
- compatibility presets for official OpenAI, `new-api`, and `sub2api`-style providers

Intentionally not implemented yet:

- a built-in browser launch UX or local callback server
- cross-platform persistent token store adapters inside the shared auth layer

Storage adapters are intentionally not part of the core runtime surface. On Apple platforms,
secure token persistence should use platform APIs such as Keychain, which are not cross-platform.
That kind of implementation belongs in a separate adapter layer, not in `AgentCore` or the shared
auth primitives. This repository now ships that separation explicitly through `AgentOpenAIAuthApple`.

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

## Examples

The repository now includes a small example matrix instead of a single thin demo:

- `OpenAIResponsesExample`: basic OpenAI Responses streaming text example
- `OpenAIToolLoopExample`: OpenAI Responses + `ToolExecutor` + visible tool loop
- `AnthropicToolLoopExample`: Anthropic Messages + `ToolExecutor` + visible tool loop
- `SessionRunnerExample`: offline demo of `AgentSessionRunner` and `AgentConversationState`
- `PersistenceExample`: offline demo of `RecordingAgentTurnRunner` and `FileAgentStore`
- `Examples/AppleHostExample`: an independent macOS SwiftUI SwiftPM project showing Browser OAuth, Keychain token storage, SwiftData session persistence, tool loop execution, and multi-turn state restoration

Build any one example:

```bash
swift build --target OpenAIToolLoopExample
```

Typical run commands:

```bash
OPENAI_API_KEY=sk-... swift run OpenAIResponsesExample "Write one sentence about Swift concurrency."
OPENAI_API_KEY=sk-... swift run OpenAIToolLoopExample "What is the weather in Paris? Use the tool."
OPENAI_ACCESS_TOKEN=eyJ... OPENAI_CHATGPT_ACCOUNT_ID=acc_... swift run OpenAIResponsesExample "Say hello"
OPENAI_ACCESS_TOKEN=eyJ... OPENAI_CHATGPT_ACCOUNT_ID=acc_... swift run OpenAIToolLoopExample "What is the weather in Paris? Use the tool."
ANTHROPIC_API_KEY=sk-ant-... swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
OPENAI_API_KEY=sk-... OPENAI_BASE_URL=https://your-openai-compatible-host/v1 swift run OpenAIToolLoopExample
OPENAI_API_KEY=sk-... OPENAI_BASE_URL=https://your-openai-compatible-host/v1 OPENAI_RESPONSES_FOLLOW_UP_STRATEGY=replay-input swift run OpenAIToolLoopExample
ANTHROPIC_API_KEY=sk-ant-... ANTHROPIC_BASE_URL=https://your-anthropic-compatible-host/v1 swift run AnthropicToolLoopExample
swift run SessionRunnerExample
swift run PersistenceExample
```

Build the independent Apple host example from its own project folder:

```bash
cd Examples/AppleHostExample
swift build --target AppleHostExample
```

Optional environment variables:

- `OPENAI_API_KEY`
- `OPENAI_ACCESS_TOKEN`
- `OPENAI_MODEL` with default `gpt-5.4`
- `OPENAI_BASE_URL` with default `https://api.openai.com/v1`
- `OPENAI_RESPONSES_FOLLOW_UP_STRATEGY` with `auto`, `previous-response-id`, or `replay-input`
- `OPENAI_CHATGPT_ACCOUNT_ID`
- `OPENAI_CHATGPT_PLAN_TYPE`
- `OPENAI_COMPAT_PROFILE` with `auto`, `openai`, `newapi`, `sub2api`, or `chatgpt-codex-oauth`
- `ANTHROPIC_API_KEY`
- `ANTHROPIC_MODEL` with default `claude-sonnet-4-20250514`
- `ANTHROPIC_BASE_URL` with default `https://api.anthropic.com/v1`
- `ANTHROPIC_VERSION` with default `2023-06-01`

## Minimal Usage

### One-turn OpenAI Responses runner

```swift
import AgentCore
import AgentOpenAI

let transport = URLSessionOpenAIResponsesTransport(
    configuration: .init(
        apiKey: apiKey,
        baseURL: URL(string: "https://api.openai.com/v1")!
    )
)
let streamingTransport = URLSessionOpenAIResponsesStreamingTransport(
    configuration: .init(
        apiKey: apiKey,
        baseURL: URL(string: "https://api.openai.com/v1")!
    )
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

### One-turn Anthropic Messages runner

```swift
import AgentCore
import AgentAnthropic

let transport = URLSessionAnthropicMessagesTransport(
    configuration: .init(
        apiKey: apiKey,
        baseURL: URL(string: "https://api.anthropic.com/v1")!,
        version: "2023-06-01"
    )
)
let client = AnthropicMessagesClient(transport: transport)

let runner = AnthropicTurnRunner(
    client: client,
    configuration: .init(
        model: "claude-sonnet-4-20250514",
        maxTokens: 1024
    )
)

for try await event in try runner.runTurn(input: [.userText("hello")]) {
    print(event)
}
```

For third-party compatible providers, point `baseURL` at the provider root that exposes the matching API shape. The OpenAI tool-loop example automatically switches its follow-up mode to `replay-input` when `OPENAI_BASE_URL` is not the official OpenAI host, because some compatible gateways implement `/responses` but not `previous_response_id` follow-ups correctly. You can override that behavior with `OPENAI_RESPONSES_FOLLOW_UP_STRATEGY`.

For ChatGPT/Codex-style bearer auth, use `AgentOpenAIAuth` with a token provider. If the host already has local tokens, `OpenAIExternalTokenProvider` is the thin path. If the host wants SDK-managed refresh on top of its own persistence, pair `OpenAIManagedTokenProvider` with a custom `OpenAITokenStore` and `OpenAITokenRefresher`, or use `OpenAIChatGPTTokenRefresher` for the official ChatGPT OAuth refresh flow. The SDK now also includes `OpenAIChatGPTBrowserFlow` and `OpenAIChatGPTDeviceCodeFlow`, aligned with the official Codex login shapes. For browser login, the SDK only generates the authorization URL and exchanges the callback URL after the host receives it; opening the browser and handling local callback delivery remain host responsibilities. On Apple platforms, `AgentOpenAIAuthApple` provides `KeychainOpenAITokenStore` as the platform-specific secure storage adapter.

### Provider-neutral session state on top of turn runners

```swift
import AgentCore

let sessionRunner = AgentSessionRunner(base: runner)
let state = AgentConversationState(sessionID: "session-1")

for try await event in try sessionRunner.runTurn(
    state: state,
    input: [.userText("hello again")]
) {
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

### File-backed persistence

```swift
import AgentPersistence

let store = try FileAgentStore(
    directoryURL: URL(fileURLWithPath: "/tmp/swift-ai-sdk-store", isDirectory: true)
)
```

## Testing

Run the full suite:

```bash
swift test
```

Key test groups:

- `AgentCoreTests`
- `AgentAnthropicTests`
- `AgentOpenAITests`
- `AgentPersistenceTests`
- `AgentMacrosTests`

The release-preparation workflow in `.github/workflows/swift-package.yml`
verifies the same root package tests and also builds/tests
`Examples/AppleHostExample` on GitHub Actions.

## Design Constraints

The current implementation follows these constraints:

- Swift-first value types are the source of truth
- provider-specific request models are adapters on top of core types
- persistence remains protocol-driven and cross-platform
- SwiftData support should be added as an adapter target, not as a hard dependency
- local and remote tools share one invocation contract from day one

## Next Work

The ordered implementation roadmap lives in [SDK_IMPROVEMENT_PLAN.md](SDK_IMPROVEMENT_PLAN.md). The core milestones in that document are now represented in code; the next useful work is likely examples, docs, additional host adapters, or deeper provider coverage rather than more baseline scaffolding.

For the first public tag, the repository-level release checklist lives in
[docs/RELEASING.md](docs/RELEASING.md).
