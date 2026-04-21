# swift-ai-sdk

[English](README.md) | [简体中文](README.zh-CN.md)

Swift-first runtime primitives for building AI hosts on Apple platforms, with a
provider-neutral core and provider-specific adapters layered on top.

## Why

- keep message, tool, session, and persistence models provider-neutral
- support both high-level "run a turn" flows and lower-level request/transport control
- let hosts opt into platform adapters such as Keychain without binding the core to Apple-only frameworks

## Status

- the first public SwiftPM tag is planned as `0.1.0`
- the repository does not have an installed external user base yet, so `0.x` releases may make breaking API changes while the public surface is still being tightened
- the current baseline is production-oriented infrastructure, not a feature-complete end-user SDK

### What works today

- OpenAI Responses request/response, SSE streaming, and Realtime turn execution
- Anthropic Messages request/response and tool-loop execution
- provider-neutral multi-turn state via `AgentConversationState` and `AgentSessionRunner`
- local and remote tools behind one execution contract
- in-memory and file-backed persistence, plus a recording runner wrapper
- ChatGPT/Codex-style authenticated Responses transports and Apple Keychain token storage

### Not in scope yet

- a built-in SwiftData adapter target
- Anthropic streaming or Realtime support
- policy or middleware interception beyond observational executor hooks
- a broader host-adapter matrix beyond the current examples

## Modules

| Module | Purpose | Layer |
| --- | --- | --- |
| `AgentCore` | Messages, stream events, sessions, tools, and runner contracts | High-level + foundational |
| `AgentOpenAI` | OpenAI Responses, Realtime, request builders, and transports | High-level + low-level |
| `AgentAnthropic` | Anthropic Messages runners, request builders, and transports | High-level + low-level |
| `AgentOpenAIAuth` | Token providers, compatibility transforms, and authenticated transports | Low-level + integration |
| `AgentOpenAIAuthApple` | Apple-specific secure token storage | Adapter |
| `AgentPersistence` | Session/turn stores, persistence records, and recording wrappers | High-level + low-level |
| `AgentMacros` | `@Tool` macro support for descriptor generation | Authoring convenience |

## Installation

After `0.1.0` is published:

```swift
dependencies: [
    .package(
        url: "https://github.com/yuemingruoan/swift-ai-sdk.git",
        from: "0.1.0"
    )
]
```

If you want the current pre-release baseline, follow `main` directly and expect
API changes:

```swift
dependencies: [
    .package(
        url: "https://github.com/yuemingruoan/swift-ai-sdk.git",
        branch: "main"
    )
]
```

Supported platforms:

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+
- visionOS 1+

## Quick Start

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

for try await event in try runner.runTurn(input: [.userText("Hello")]) {
    print(event)
}
```

For provider-neutral multi-turn state:

```swift
let sessionRunner = AgentSessionRunner(base: runner)
let state = AgentConversationState(sessionID: "session-1")

for try await event in try sessionRunner.runTurn(
    state: state,
    input: [.userText("Hello again")]
) {
    print(event)
}
```

## Lower-Level APIs

The high-level runners are only one layer of the package. If your host needs
custom request shaping, transport control, or auth wiring, the lower-level APIs
are public and documented as well.

Examples:

- `OpenAIResponseRequest` and `OpenAIResponseInputBuilder` for building raw Responses payloads
- `OpenAIResponsesRequestBuilder`, `URLSessionOpenAIResponsesTransport`, and `URLSessionOpenAIResponsesStreamingTransport` for direct HTTP and SSE control
- `OpenAIRealtimeRequestBuilder` and the Realtime WebSocket client types for lower-level event flows
- `AnthropicMessagesRequest`, `AnthropicMessagesRequestBuilder`, and `URLSessionAnthropicMessagesTransport` for direct Anthropic request control
- `OpenAITokenProvider`, `OpenAIAuthenticatedResponsesRequestBuilder`, and authenticated transports for ChatGPT/Codex-style bearer flows
- `AgentSessionStore`, `AgentTurnStore`, `FileAgentStore`, and persistence record mappers when the host needs direct persistence control

## Examples

- `OpenAIResponsesExample` for the simplest OpenAI Responses text flow
- `OpenAIToolLoopExample` for OpenAI tool-loop execution
- `AnthropicToolLoopExample` for Anthropic tool-loop execution
- `SessionRunnerExample` for provider-neutral multi-turn state
- `PersistenceExample` for persisted turn recording
- `Examples/AppleHostExample` for a standalone macOS SwiftUI host app with Browser OAuth, Keychain storage, SwiftData persistence, and tool execution

Typical commands:

```bash
swift run OpenAIResponsesExample "Write one sentence about Swift concurrency."
swift run OpenAIToolLoopExample "What is the weather in Paris? Use the tool."
swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
swift run SessionRunnerExample
swift run PersistenceExample
cd Examples/AppleHostExample && swift build --target AppleHostExample
```

## Documentation

- public API entrypoints now use Swift-style doc comments
- the documented surface covers both high-level APIs and lower-level builders, request models, and transports
- the release checklist for the first public tag lives in [docs/RELEASING.md](docs/RELEASING.md)

## Validation

Run the root package tests:

```bash
swift test
```

Run the standalone Apple host example tests:

```bash
cd Examples/AppleHostExample
swift test
```

GitHub Actions runs the same validation from
`.github/workflows/swift-package.yml`.
