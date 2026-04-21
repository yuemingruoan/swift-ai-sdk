# Error Handling Cookbook

This note turns the SDK error taxonomy into host-facing handling patterns.
It does not replace the API docs or the taxonomy reference in
`docs/SDK_ERRORS_AND_TRANSPORT.md`; it focuses on what hosts should usually do
next when a specific error class appears.

## Quick Triage Table

| Error type | Typical meaning | Retry? | What to log | Host action |
| --- | --- | --- | --- | --- |
| `AgentProviderError` | The provider responded, but not with success. | Sometimes. Usually yes for `429`, `500`, `502`, `503`, `504`; usually no for persistent `400`-class failures. | Provider, status code, request ID, model, endpoint family. | Apply product retry policy, back off on rate limit, surface actionable provider failures to the user. |
| `AgentTransportError` | The request did not complete cleanly or no valid HTTP/WebSocket state was available. | Usually yes if the failure is transient. | Provider, request ID, transport path, underlying description. | Retry if the operation is idempotent, or ask the user to reconnect/retry. |
| `AgentDecodingError` | The SDK could not encode the outgoing request or decode/project the incoming payload. | Usually no. | Provider, operation, model, request ID, decode/projection description. | Treat as an integration or contract mismatch; inspect input shape, stored payloads, or provider response changes. |
| `AgentRuntimeError` | Higher-level orchestration failed even though the raw transport might be healthy. | Rarely automatic. | Provider, guardrail value, session or turn context. | Adjust host policy, tool loop limits, or prompt/tool design. |
| `AgentAuthError` | Token lookup, refresh, OAuth callback, compatibility auth, or secure storage failed. | Depends on subtype. | Auth method, provider if present, account/session identifiers when safe. | Re-authenticate, refresh tokens, prompt the user, or surface secure-storage diagnostics. |
| `AgentStreamError` | The streaming protocol failed after the request was accepted. | Sometimes. | Provider, request ID, event type, stream status or error fields. | Reconnect or fall back to non-streaming if the host supports it. |
| `AgentPersistenceError` | Persisted state could not be read or written safely. | Usually no for invalid data; maybe yes for transient write failures. | File name, session identifier, operation. | Stop automatic overwrite, preserve user data, and surface recovery options. |
| `OpenAIConversionError`, `AnthropicConversionError` | The SDK/provider shape conversion failed deterministically. | No. | Operation, offending role/part/call ID. | Treat as unsupported host input or an SDK/provider contract bug. |

## Recommended Branching Pattern

Hosts should branch first on failure class, not provider-specific text. A common
shape is:

```swift
do {
    let projection = try await client.resolveToolCalls(request, using: executor)
    render(projection)
} catch let error as AgentProviderError {
    handleProviderError(error)
} catch let error as AgentTransportError {
    handleTransportError(error)
} catch let error as AgentDecodingError {
    handleDecodingError(error)
} catch let error as AgentRuntimeError {
    handleRuntimeError(error)
} catch let error as AgentAuthError {
    handleAuthError(error)
} catch let error as AgentStreamError {
    handleStreamError(error)
} catch let error as AgentPersistenceError {
    handlePersistenceError(error)
} catch {
    handleUnexpectedError(error)
}
```

The conversion-specific enums are intentionally not folded into the shared
taxonomy. Catch them explicitly where you build provider requests or project
provider payloads.

## Per-Class Guidance

### `AgentProviderError`

Use `statusCode` to separate product behavior:

- `429`: back off and consider showing a rate-limit-specific message.
- `500`, `502`, `503`, `504`: transient server failure; retry if the operation
  is safe to repeat.
- `400` or `404`: usually malformed request, unsupported model/path, or wrong
  host configuration; inspect the request and endpoint family before retrying.
- `401` or `403`: often belongs to auth/config handling rather than generic
  retry. Correlate with token source, account ID, or compatibility profile.

### `AgentTransportError`

This class is about execution and connectivity, not model semantics.

Common host responses:

- queue one bounded retry for idempotent operations
- surface an offline/reconnect state in UI
- include request ID, provider, and transport family in diagnostics

`notConnected(provider:)` in realtime flows usually means the host failed to
connect or disconnected too early, not that the model request itself was bad.

### `AgentDecodingError`

Default stance: do not auto-retry until you know why decoding failed.

Good first questions:

- Did the host send unsupported message parts or roles?
- Did persisted data drift from the expected shape?
- Did the provider change its payload unexpectedly?

If the error is `requestEncoding`, inspect the host-generated input. If it is
`responseBody` or `responseProjection`, inspect provider payload capture,
fixtures, and recent provider contract changes.

### `AgentRuntimeError`

Current public runtime guardrail:

- `toolCallLimitExceeded(provider:maxIterations:)`

This is a host policy failure, not a transport failure. Typical responses:

- increase the iteration budget only if the tool loop is legitimately bounded
- improve tool descriptions or prompts so the model terminates earlier
- add UI or logs that show repeated tool loops clearly

### `AgentAuthError`

Split auth handling by subtype:

- `missingCredentials`, `refreshUnsupported`, `unauthorized`: usually requires
  re-authentication, a different token source, or a user-visible recovery path.
- browser/OAuth flow cases such as `stateMismatch`,
  `missingAuthorizationCode`, `callbackError`, `unknownAuthorizationSession`:
  treat as flow-state failures, not transport failures.
- `secureStorageFailure`: keep the raw status code in logs and surface a
  storage-specific host diagnostic.
- `invalidStoredCredentials`: treat stored tokens as corrupt or stale and avoid
  silently trusting them again.

### `AgentStreamError`

Streaming failures benefit from graceful degradation:

- if the host supports it, retry once or fall back to non-streaming
- capture request ID and stream event context
- surface partial output carefully; do not imply completion if the stream
  failed before a terminal event

### `AgentPersistenceError`

For `invalidPersistedData`, the safest default is:

- fail explicitly
- preserve the original file
- prompt for repair, reset, or export rather than overwriting automatically

For write failures, capture file name and operation context. Hosts should avoid
claiming that a conversation was saved if the write failed.

## Logging Checklist

For operational logs, prefer structured fields over prose:

- error class
- provider
- request ID if available
- model
- endpoint family or transport family
- session or turn identifier
- retry attempt count
- safe auth/session metadata when relevant

Avoid logging raw tokens, full sensitive prompts, or unredacted persisted user
data.

## Suggested UI Mapping

| Error class | Suggested user-facing tone |
| --- | --- |
| Provider / Transport / Stream | Temporary failure or connectivity/service issue. |
| Decoding / Conversion-specific | Unsupported input or internal compatibility issue. |
| Runtime | Tool loop or orchestration limit reached. |
| Auth | Sign-in, token, or permission problem. |
| Persistence | Local save/load issue that may require user action. |

## Out Of Scope

This cookbook does not prescribe:

- exact retry counts for every product
- telemetry schema design
- provider-specific moderation or abuse handling
- middleware/policy behavior planned for later roadmap milestones
