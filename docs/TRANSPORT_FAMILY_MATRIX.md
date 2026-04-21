# Transport Family Matrix

This matrix summarizes the current transport and request-builder surfaces that
exist in the repository today. It is meant to help hosts answer two practical
questions quickly:

1. which transport family should I use for a given integration shape?
2. which knobs are shared across families, and which are family-specific?

## Family Overview

| Family | Primary types | Provider(s) | Protocol | Current scope |
| --- | --- | --- | --- | --- |
| Direct OpenAI HTTP | `OpenAIResponsesRequestBuilder`, `URLSessionOpenAIResponsesTransport` | OpenAI | HTTP JSON | One-shot Responses request/response |
| Direct OpenAI SSE | `OpenAIResponsesRequestBuilder`, `URLSessionOpenAIResponsesStreamingTransport` | OpenAI | HTTP SSE | Streamed Responses events |
| OpenAI Realtime WebSocket | `OpenAIRealtimeRequestBuilder`, `OpenAIRealtimeWebSocketClient` | OpenAI | WebSocket | Realtime event loop and turn execution |
| OpenAI Responses WebSocket | `OpenAIResponsesWebSocketRequestBuilder`, `URLSessionOpenAIResponsesWebSocketTransport` | OpenAI | WebSocket | Streamed Responses over WebSocket |
| Direct Anthropic HTTP | `AnthropicMessagesRequestBuilder`, `URLSessionAnthropicMessagesTransport` | Anthropic | HTTP JSON | Messages request/response and tool loop |
| Authenticated OpenAI-compatible HTTP | `OpenAIAuthenticatedResponsesRequestBuilder`, `URLSessionOpenAIAuthenticatedResponsesTransport` | OpenAI-compatible | HTTP JSON | ChatGPT/Codex-style authenticated Responses |
| Authenticated OpenAI-compatible SSE | `OpenAIAuthenticatedResponsesRequestBuilder`, `URLSessionOpenAIAuthenticatedResponsesStreamingTransport` | OpenAI-compatible | HTTP SSE | Authenticated streamed Responses |
| Authenticated OpenAI-compatible WebSocket | `OpenAIAuthenticatedResponsesWebSocketRequestBuilder`, `URLSessionOpenAIAuthenticatedResponsesWebSocketTransport` | OpenAI-compatible | WebSocket | Authenticated streamed Responses over WebSocket |

## Configuration Matrix

| Capability | Direct OpenAI HTTP/SSE | Direct Anthropic HTTP | OpenAI Realtime WebSocket | OpenAI Responses WebSocket | Authenticated OpenAI-compatible HTTP/SSE | Authenticated OpenAI-compatible WebSocket |
| --- | --- | --- | --- | --- | --- | --- |
| Shared `AgentHTTPTransportConfiguration` | Yes | Yes | No | No | Yes | Header-oriented subset only |
| `timeoutInterval` | Yes | Yes | No | No | Yes | No |
| `retryPolicy` | Yes | Yes | No | No | Yes | No |
| `additionalHeaders` | Yes | Yes | Yes, via family config | Yes, via family config | Yes | Yes |
| `userAgent` | Yes | Yes | Yes | Yes | Yes | Yes |
| `requestID` / request header | `X-Request-Id` | `X-Request-Id` | Family-specific only | `x-client-request-id` | `X-Request-Id` | `X-Request-Id` plus `x-client-request-id` when provided |
| Injected session/test double | Yes | Yes | Yes | Yes | Yes | Yes |
| Compatibility-specific headers | No | No | Sometimes | Sometimes | Yes | Yes |

## Choosing A Family

### Use direct OpenAI HTTP or SSE when:

- you have a plain OpenAI API key
- you want the most neutral OpenAI Responses surface
- you want the shared HTTP transport configuration directly

### Use Anthropic HTTP when:

- you are integrating Anthropic Messages today
- you need request/response or tool-loop execution
- you do not need Anthropic streaming yet

### Use authenticated OpenAI-compatible transports when:

- you are targeting ChatGPT/Codex-style bearer tokens or compatible backends
- you need compatibility transforms and auth-aware header shaping
- you still want shared timeout/retry/header config for HTTP/SSE

### Use WebSocket families when:

- you explicitly need a WebSocket flow
- you understand that WebSocket config is not identical to the shared HTTP config
- you are prepared to handle stream lifecycle and connection management directly

## Error Surface By Family

| Family | Most common SDK-facing errors |
| --- | --- |
| HTTP request/response families | `AgentProviderError`, `AgentTransportError`, `AgentDecodingError`, `AgentAuthError` for authenticated families |
| SSE families | Same as HTTP plus `AgentStreamError` |
| Realtime and WebSocket families | `AgentTransportError`, `AgentDecodingError`, `AgentRuntimeError`, plus `AgentStreamError` where streamed event projection fails |
| File-backed host flows around any family | `AgentPersistenceError` when persistence is involved |

Conversion-specific errors remain outside this matrix because they are about
provider-shape mapping, not transport family choice.

## Current Gaps

This matrix reflects current repository reality, not future intent:

- Anthropic streaming is not yet present.
- WebSocket families do not share the full HTTP transport config.
- Authenticated families still expose additional compatibility knobs beyond the
  shared transport surface.
- The matrix is transport-focused; it does not replace the provider capability
  matrix in the README.
