# swift-ai-sdk

[English](README.md) | [简体中文](README.zh-CN.md)

Swift-first runtime primitives for building AI hosts on Apple platforms, with a
provider-neutral core and provider-specific adapters layered on top.

## Why

- keep message, tool, session, and persistence models provider-neutral
- support both high-level "run a turn" flows and lower-level request/transport control
- let hosts opt into platform adapters such as Keychain without binding the core to Apple-only frameworks

## Status

- `v0.3.0` was released on 2026-04-22 as the current public SwiftPM baseline
- `v0.1.0` remains the first public SwiftPM tag
- `main` is the active development line for follow-up work such as `v0.4.0`
- the repository does not have an installed external user base yet, so `0.x` releases may make breaking API changes while the public surface is still being tightened
- breaking changes during `0.x` should be called out explicitly in `CHANGELOG.md` and GitHub Release notes
- the current baseline is production-oriented infrastructure, not a feature-complete end-user SDK

### What works today

- OpenAI Responses request/response, SSE streaming, and Realtime turn execution
- Anthropic Messages request/response, SSE streaming, and tool-loop execution
- provider-native web search request modeling for OpenAI and Anthropic official built-in search tools
- provider-neutral multi-turn state via `AgentConversationState` and `AgentSessionRunner`
- local and remote tools behind one execution contract
- split runtime middleware for model request/response interception, tool authorization, message redaction, and structured audit events
- in-memory and file-backed persistence, plus a recording runner wrapper
- ChatGPT/Codex-style authenticated Responses transports and Apple Keychain token storage

### Not in scope yet

- a built-in SwiftData adapter target
- Anthropic Realtime support
- a broader host-adapter matrix beyond the current examples

### Provider Feature Matrix

| Capability | OpenAI | Anthropic |
| --- | --- | --- |
| Request / response | Yes | Yes |
| Streaming | Yes, SSE Responses streaming | Yes, SSE Messages streaming |
| Realtime | Yes | Not yet |
| Tool loop | Yes | Yes |
| Official web search tool | Yes, built-in `web_search` tool | Yes, built-in `web_search_*` server tool |
| Auth helpers | Yes, ChatGPT/Codex-style authenticated transports | Not yet |
| Transport customization | Yes, shared HTTP transport options | Yes, shared HTTP transport options |

## Modules

| Module | Purpose | Layer |
| --- | --- | --- |
| `OpenAIResponsesAPI` | Raw OpenAI Responses request/response models, built-in tools, builders, transports, and raw streaming events | Low-level |
| `OpenAIAgentRuntime` | High-level OpenAI projections, turn runners, tool-loop orchestration, and runtime streaming helpers | High-level |
| `AnthropicMessagesAPI` | Raw Anthropic Messages request/response models, built-in tools, builders, transports, and raw streaming events | Low-level |
| `AnthropicAgentRuntime` | High-level Anthropic projections, turn runners, tool-loop orchestration, and streaming helpers | High-level |
| `OpenAIAuthentication` | Token providers, compatibility transforms, and authenticated OpenAI-compatible transports | Integration |
| `OpenAIAppleAuthentication` | Apple-specific secure token storage adapters | Adapter |
| `AgentPersistence` | Session/turn stores, persistence records, and recording wrappers | Standalone |
| `AgentMacros` | `@Tool` macro support for descriptor generation | Authoring convenience |

`AgentCore` remains in the package as an implementation layer but is no longer a public product.

## Installation

`v0.3.0` is the current public SwiftPM baseline:

```swift
dependencies: [
    .package(
        url: "https://github.com/yuemingruoan/swift-ai-sdk.git",
        from: "0.3.0"
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

If you are moving from `v0.2.0`-style imports to the `v0.3.0` public module
surface, see [docs/MIGRATING_TO_V0_3_0.md](docs/MIGRATING_TO_V0_3_0.md).

Supported platforms:

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+
- visionOS 1+

## Quick Start

```swift
import OpenAIResponsesAPI
import OpenAIAgentRuntime

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
- `AnthropicMessagesRequest`, `AnthropicMessagesRequestBuilder`, `URLSessionAnthropicMessagesTransport`, and `URLSessionAnthropicMessagesStreamingTransport` for direct Anthropic JSON and SSE control
- OpenAI `web_search` and Anthropic `web_search_*` built-in tool declarations at the provider request layer when you want official server-side web search rather than SDK-managed remote tools
- `AnthropicMessageResponse` and raw stream events preserve Anthropic `server_tool_use`, `web_search_tool_result`, text citations, and `usage.server_tool_use.web_search_requests`; `AnthropicAgentRuntime` intentionally projects those built-in traces down to assistant text unless you opt into the raw API surface
- `AnthropicMessageResponse.webSearchOutput()` when you want a provider-native Claude Code-style summary of Anthropic web-search blocks without leaving the low-level API layer
- `OpenAITokenProvider`, `OpenAIAuthenticatedResponsesRequestBuilder`, and authenticated transports for ChatGPT/Codex-style bearer flows
- `AgentSessionStore`, `AgentTurnStore`, `FileAgentStore`, and persistence record mappers when the host needs direct persistence control
- `AgentMiddlewareStack` plus split middleware protocols when the host needs request/response interception, tool authorization, message redaction, or structured audit recording

## SDK Error Taxonomy

The SDK-facing error surface is intentionally layered so hosts can distinguish
provider failures from transport, decoding, runtime, auth, stream, and
persistence failures.

| Layer | Public type(s) | Typical meaning |
| --- | --- | --- |
| Provider | `AgentProviderError` | The provider returned a valid HTTP response with a non-2xx status code. |
| Transport | `AgentTransportError` | The request could not be executed cleanly, the response was not a valid `HTTPURLResponse`, the connection was unavailable, or retries were exhausted. |
| Decoding | `AgentDecodingError` | Request encoding, response JSON decoding, or provider-to-SDK projection failed. |
| Runtime | `AgentRuntimeError` | A higher-level orchestration rule failed, such as tool-loop iteration limits or middleware-driven tool denial. |
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
import AnthropicMessagesAPI
import OpenAIAuthentication
import OpenAIResponsesAPI
import Foundation

let transportConfiguration = AgentHTTPTransportConfiguration(
    timeoutInterval: 30,
    retryPolicy: .init(
        maxAttempts: 3,
        backoff: .constant(milliseconds: 500)
    ),
    additionalHeaders: ["X-Client-Name": "ExampleHost"],
    userAgent: "ExampleHost/0.2.0",
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

let anthropicStreamingTransport = URLSessionAnthropicMessagesStreamingTransport(
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
- `AnthropicToolLoopExample` for Anthropic tool-loop execution, optional SSE streaming, and middleware smoke testing
- `SessionRunnerExample` for provider-neutral multi-turn state through the new runtime-facing import surface
- `PersistenceExample` for persisted turn recording through the standalone `AgentPersistence` product
- `Examples/AppleHostExample` for a standalone macOS SwiftUI host app with Browser OAuth, Keychain storage, SwiftData persistence, and tool execution

Typical commands:

```bash
swift run OpenAIResponsesExample "Write one sentence about Swift concurrency."
swift run OpenAIToolLoopExample "What is the weather in Paris? Use the tool."
swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
ANTHROPIC_STREAM=true EXAMPLE_PRINT_AUDIT=true swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
ANTHROPIC_STREAM=true EXAMPLE_DENY_TOOL=lookup_weather swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
ANTHROPIC_INCLUDE_THINKING=true swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
swift run SessionRunnerExample
swift run PersistenceExample
cd Examples/AppleHostExample && swift build --target AppleHostExample
```

Opt-in live smoke commands:

```bash
TOKENS_JSON=$(security find-generic-password -s dev.swift-ai-sdk.apple-host-example -a chatgpt-auth -w)
OPENAI_AUTH_LIVE_SMOKE=true \
OPENAI_ACCESS_TOKEN=$(printf '%s' "$TOKENS_JSON" | jq -r '.accessToken') \
OPENAI_CHATGPT_ACCOUNT_ID=$(printf '%s' "$TOKENS_JSON" | jq -r '.chatGPTAccountID') \
OPENAI_CHATGPT_PLAN_TYPE=$(printf '%s' "$TOKENS_JSON" | jq -r '.chatGPTPlanType') \
OPENAI_AUTH_BASE_URL=https://chatgpt.com/backend-api/codex \
swift test --filter OpenAIAuthLiveSmokeTests

cd Examples/AppleHostExample
APPLE_HOST_EXAMPLE_LIVE_SMOKE=true swift test --filter AppleHostExampleLiveSmokeTests

cd ../..
ANTHROPIC_WEB_SEARCH_LIVE_SMOKE=true swift test --filter AnthropicWebSearchLiveSmokeTests
```

The Anthropic web-search live smoke depends on the configured backend actually
supporting Anthropic `web_search_*` server tools. Compatible OpenAI-style relay
backends may still time out or flatten the response shape instead of returning
official `server_tool_use` / `web_search_tool_result` blocks.

Anthropic raw responses and raw streaming events preserve provider `thinking`
blocks. The convenience projection layer defaults to omitting them, and callers
can opt back in through `AnthropicProjectionOptions.preserveThinking` or
`AnthropicTurnRunnerConfiguration(..., projectionOptions: .preserveThinking)`.

## Documentation

- the active docs set is indexed in [docs/README.md](docs/README.md)
- public API entrypoints now use Swift-style doc comments
- the documented surface covers both high-level APIs and lower-level builders, request models, transports, runtime middleware, and Anthropic streaming raw/projection boundaries
- the README now documents the SDK-facing error taxonomy and the shared HTTP transport configuration surface
- conversion-layer failures remain intentionally provider-specific via `OpenAIConversionError` and `AnthropicConversionError`
- a longer reference for these two topics lives in [docs/SDK_ERRORS_AND_TRANSPORT.md](docs/SDK_ERRORS_AND_TRANSPORT.md)
- a host-facing error handling guide lives in [docs/ERROR_HANDLING_COOKBOOK.md](docs/ERROR_HANDLING_COOKBOOK.md)
- a transport family comparison lives in [docs/TRANSPORT_FAMILY_MATRIX.md](docs/TRANSPORT_FAMILY_MATRIX.md)
- a runtime middleware guide lives in [docs/MIDDLEWARE_GUIDE.md](docs/MIDDLEWARE_GUIDE.md)
- a breaking-change migration guide for the new public module surface lives in [docs/MIGRATING_TO_V0_3_0.md](docs/MIGRATING_TO_V0_3_0.md)
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
