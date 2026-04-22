# SDK Errors And Shared Transport Configuration

This note documents the current public surface for two topics
that SDK integrators routinely need to reason about:

- the shared SDK-facing error taxonomy
- the shared HTTP transport configuration used by direct OpenAI and Anthropic transports

It is intentionally descriptive rather than aspirational. If a type or knob is
not listed here, this document is not promising it for a given release.

## Error Taxonomy

The SDK exposes a layered error model so hosts can branch on failure class
without parsing provider-specific strings.

| Layer | Public type(s) | What it covers | Typical examples |
| --- | --- | --- | --- |
| Provider | `AgentProviderError` | A provider returned a valid HTTP response with a non-success status. | `401`, `429`, or `500` from OpenAI or Anthropic after the transport completed normally. |
| Transport | `AgentTransportError` | Request execution, connectivity, or response-shape failures below model decoding. | `URLSession` failure, missing `HTTPURLResponse`, disconnected realtime socket, retry policy exhaustion. |
| Decoding | `AgentDecodingError` | Encoding outgoing requests, decoding incoming payloads, or projecting decoded provider payloads into SDK shapes. | JSON encode failure for a request body, JSON decode failure for a response body, response projection mismatch. |
| Runtime | `AgentRuntimeError` | Multi-step orchestration above the raw provider transport. | Tool-loop iteration budget exceeded, tool call denied by runtime policy. |
| Auth | `AgentAuthError` | Token providers, OAuth/browser flows, compatibility-profile auth, and secure token storage. | Missing refresh token, browser callback state mismatch, unsupported authorization method, Keychain failure. |
| Stream | `AgentStreamError` | Streaming protocol failures after the request is accepted. | SSE event decoding failure, streamed response status failure, provider stream server error event. |
| Persistence | `AgentPersistenceError` | File-backed persistence read/write failures. | Invalid persisted JSON, failed session or turn file write. |
| Conversion-specific | `OpenAIConversionError`, `AnthropicConversionError` | Deterministic provider-shaping failures that stay provider-specific on purpose. | Unsupported message roles, unsupported content blocks, invalid function-call arguments. |

### Shared Versus Provider-Specific Errors

The `Agent*Error` types are the SDK-facing taxonomy. When provider identity
matters, they carry `AgentProviderID`, so the host can branch on `openai` versus
`anthropic` without losing the higher-level failure class.

The conversion enums are intentionally different. They describe deterministic
shape mismatches while converting between SDK models and provider wire models,
not request execution failures. They should usually be treated as integration
bugs or unsupported-input cases, not transient transport failures.

### Practical Handling Guidance

- Treat `AgentProviderError`, `AgentTransportError`, `AgentAuthError`, and many
  `AgentStreamError` cases as runtime failures worth logging with request
  metadata and retry context.
- Treat `AgentDecodingError`, conversion-specific errors, and
  `AgentPersistenceError.invalidPersistedData` as signals to inspect host input,
  stored data, or a provider contract mismatch.
- Treat `AgentRuntimeError` as an orchestration policy signal: the transport may
  be healthy even though the higher-level loop hit its guardrails.

## Shared HTTP Transport Configuration

`AgentHTTPTransportConfiguration` is the common configuration type used by:

- `OpenAIAPIConfiguration.transport`
- `AnthropicAPIConfiguration.transport`
- `OpenAIAuthenticatedAPIConfiguration.transport`

That shared surface currently applies to the direct `URLSession`-backed HTTP
transports:

- `URLSessionOpenAIResponsesTransport`
- `URLSessionOpenAIResponsesStreamingTransport`
- `URLSessionAnthropicMessagesTransport`
- `URLSessionAnthropicMessagesStreamingTransport`
- `URLSessionOpenAIAuthenticatedResponsesTransport`
- `URLSessionOpenAIAuthenticatedResponsesStreamingTransport`

### Supported Knobs

| Knob | Behavior |
| --- | --- |
| `timeoutInterval` | Copied onto each generated `URLRequest.timeoutInterval`. |
| `retryPolicy.maxAttempts` | Total number of attempts, including the initial attempt. |
| `retryPolicy.backoff` | Retry delay strategy. The current public cases are `.none` and `.constant(milliseconds:)`. |
| `retryPolicy.retryableStatusCodes` | Status codes that trigger a retry before provider error mapping. The default set is `408`, `429`, `500`, `502`, `503`, `504`. |
| `additionalHeaders` | Additional request headers added to every generated request. |
| `userAgent` | Sets `User-Agent`. If both the top-level provider config and `transport.userAgent` are set, the transport-level value wins. |
| `requestID` | Sets the `X-Request-Id` header. |

### Example

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

let openAIStreamingTransport = URLSessionOpenAIResponsesStreamingTransport(
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

### Injected Session Boundaries

The HTTP transports above support session injection so hosts can supply an
ephemeral `URLSession`, a custom protocol-backed session, or a test double:

- `URLSessionOpenAIResponsesTransport(..., session: any OpenAIHTTPSession)`
- `URLSessionOpenAIResponsesStreamingTransport(..., session: any OpenAIHTTPLineStreamingSession)`
- `URLSessionAnthropicMessagesTransport(..., session: any AnthropicHTTPSession)`
- `URLSessionAnthropicMessagesStreamingTransport(..., session: any AnthropicHTTPLineStreamingSession)`

Authenticated OpenAI-compatible Responses transports also support injected
sessions and now consume the same shared transport configuration:

- `URLSessionOpenAIAuthenticatedResponsesTransport(..., session: any OpenAIHTTPSession)`
- `URLSessionOpenAIAuthenticatedResponsesStreamingTransport(..., session: any OpenAIHTTPLineStreamingSession)`

Their public config surface is still `OpenAIAuthenticatedAPIConfiguration`,
because authenticated compatibility settings such as `originator` and
`Accept-Language` remain separate from the shared transport knobs.

OpenAI WebSocket transports still keep a separate config surface because they
are not plain HTTP request/response transports. The authenticated WebSocket
builder does, however, reuse the header-oriented subset of
`AgentHTTPTransportConfiguration`:

- `additionalHeaders`
- `userAgent`
- `requestID`

It does not use HTTP-only knobs such as `timeoutInterval` or `retryPolicy`.

## Middleware Note

`AgentMiddlewareStack` lives above the raw transport layer. It governs model
request/response interception, tool authorization, message redaction, and audit
recording in the runtime layer, while `AgentHTTPTransportConfiguration`
continues to describe the shared HTTP request-level knobs for direct
OpenAI/Anthropic transports.

## Anthropic Thinking Boundary

Anthropic raw response surfaces preserve provider thinking blocks:

- `AnthropicMessageResponse.content`
- `AnthropicMessageStreamEvent`
- `AnthropicMessagesClient.createMessage(_:)`
- `AnthropicMessagesStreamingTransport.streamMessage(_:)`

The convenience projection layer is where callers decide whether that thinking
should stay in provider-neutral output:

- `AnthropicMessageResponse.projectedOutput(options:)`
- `AnthropicMessagesClient.createProjectedResponse(_:options:)`
- `AnthropicMessagesClient.projectedResponseEvents(..., projectionOptions:)`
- `AnthropicTurnRunnerConfiguration.projectionOptions`

The current convenience default is `AnthropicProjectionOptions.omitThinking`.
Callers that want projected thinking can opt into
`AnthropicProjectionOptions.preserveThinking`.

## Out Of Scope For This Note

This document does not promise:

- observability APIs beyond the current request ID and user-agent hooks
- a future collapse of authenticated or WebSocket transport config into one universal transport type
