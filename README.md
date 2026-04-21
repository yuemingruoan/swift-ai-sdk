# swift-ai-sdk

[English](README.md) | [简体中文](README.zh-CN.md)

Swift-first runtime primitives for building AI hosts on Apple platforms, with a
provider-neutral core and provider-specific adapters layered on top.

## Why

- keep message, tool, session, and persistence models provider-neutral
- support both high-level "run a turn" flows and lower-level request/transport control
- let hosts opt into platform adapters such as Keychain without binding the core to Apple-only frameworks

## Status

- `v0.1.0` was released on 2026-04-21 as the first public SwiftPM tag
- `main` is the active development line for follow-up work such as `v0.1.1`
- the repository does not have an installed external user base yet, so `0.x` releases may make breaking API changes while the public surface is still being tightened
- breaking changes during `0.x` should be called out explicitly in `CHANGELOG.md` and GitHub Release notes
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

### Provider Feature Matrix

| Capability | OpenAI | Anthropic |
| --- | --- | --- |
| Request / response | Yes | Yes |
| Streaming | Yes, SSE Responses streaming | Not yet |
| Realtime | Yes | Not yet |
| Tool loop | Yes | Yes |
| Auth helpers | Yes, ChatGPT/Codex-style authenticated transports | Not yet |
| Transport customization | Yes, shared HTTP transport options | Yes, shared HTTP transport options |

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

`v0.1.0` is the current public SwiftPM baseline:

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

## SDK Error Taxonomy

The SDK-facing error surface is intentionally layered so hosts can distinguish
provider failures from transport, decoding, runtime, auth, stream, and
persistence failures.

| Layer | Public type(s) | Typical meaning |
| --- | --- | --- |
| Provider | `AgentProviderError` | The provider returned a valid HTTP response with a non-2xx status code. |
| Transport | `AgentTransportError` | The request could not be executed cleanly, the response was not a valid `HTTPURLResponse`, the connection was unavailable, or retries were exhausted. |
| Decoding | `AgentDecodingError` | Request encoding, response JSON decoding, or provider-to-SDK projection failed. |
| Runtime | `AgentRuntimeError` | A higher-level orchestration rule failed, such as tool-loop iteration limits. |
| Auth | `AgentAuthError` | Token lookup/refresh, OAuth callback, compatibility-profile auth, or secure storage failed. |
| Stream | `AgentStreamError` | SSE or other streaming responses failed at the event/protocol layer. |
| Persistence | `AgentPersistenceError` | File-backed state could not be read as valid persisted data or could not be written. |
| Conversion-specific | `OpenAIConversionError`, `AnthropicConversionError` | Deterministic provider-shaping failures that remain provider-specific instead of being folded into the shared SDK taxonomy. |

When a shared error depends on a provider boundary, it carries `AgentProviderID`
so hosts can log or branch on `openai` vs `anthropic` without parsing strings.

## Shared HTTP Transport Configuration

`AgentHTTPTransportConfiguration` is the shared configuration surface for the
direct `URLSession`-backed OpenAI and Anthropic HTTP transports, plus the
authenticated OpenAI-compatible Responses HTTP/SSE transports:

- `timeoutInterval`: copied onto each generated `URLRequest`
- `retryPolicy.maxAttempts`: total attempts, including the initial request
- `retryPolicy.backoff`: currently `.none` or `.constant(milliseconds:)`
- `retryPolicy.retryableStatusCodes`: defaults to `408`, `429`, `500`, `502`, `503`, and `504`
- `additionalHeaders`: appended to each generated request
- `userAgent`: sets `User-Agent` and overrides the top-level config `userAgent` when both are present
- `requestID`: sets the `X-Request-Id` header

```swift
import AgentCore
import AgentAnthropic
import AgentOpenAI
import Foundation

let transportConfiguration = AgentHTTPTransportConfiguration(
    timeoutInterval: 30,
    retryPolicy: .init(
        maxAttempts: 3,
        backoff: .constant(milliseconds: 500)
    ),
    additionalHeaders: ["X-Client-Name": "ExampleHost"],
    userAgent: "ExampleHost/0.1.1",
    requestID: UUID().uuidString
)

let session = URLSession(configuration: .ephemeral)

let openAITransport = URLSessionOpenAIResponsesTransport(
    configuration: .init(
        apiKey: openAIKey,
        transport: transportConfiguration
    ),
    session: session
)

let anthropicTransport = URLSessionAnthropicMessagesTransport(
    configuration: .init(
        apiKey: anthropicKey,
        transport: transportConfiguration
    ),
    session: session
)

let authenticatedTransport = URLSessionOpenAIAuthenticatedResponsesTransport(
    configuration: .init(
        transport: transportConfiguration
    ),
    tokenProvider: tokenProvider,
    session: session
)
```

The same shared transport config also applies to
`URLSessionOpenAIResponsesStreamingTransport` and
`URLSessionOpenAIAuthenticatedResponsesStreamingTransport`. For authenticated
Requests, `OpenAIAuthenticatedAPIConfiguration` now embeds that shared
transport config while still exposing compatibility-specific settings such as
`originator` and `Accept-Language`.

OpenAI WebSocket transports still keep a separate config shape, but the
authenticated WebSocket builder now reuses the header-oriented subset of the
shared transport config: `additionalHeaders`, `userAgent`, and `requestID`.

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

- the active docs set is indexed in [docs/README.md](docs/README.md)
- public API entrypoints now use Swift-style doc comments
- the documented surface covers both high-level APIs and lower-level builders, request models, and transports
- the README now documents the SDK-facing error taxonomy and the shared HTTP transport configuration surface
- conversion-layer failures remain intentionally provider-specific via `OpenAIConversionError` and `AnthropicConversionError`
- a longer reference for these two topics lives in [docs/SDK_ERRORS_AND_TRANSPORT.md](docs/SDK_ERRORS_AND_TRANSPORT.md)
- a host-facing error handling guide lives in [docs/ERROR_HANDLING_COOKBOOK.md](docs/ERROR_HANDLING_COOKBOOK.md)
- a transport family comparison lives in [docs/TRANSPORT_FAMILY_MATRIX.md](docs/TRANSPORT_FAMILY_MATRIX.md)
- release governance and tag conventions live in [docs/RELEASING.md](docs/RELEASING.md)
- forward-looking version milestones live in [ROADMAP.md](ROADMAP.md)

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
