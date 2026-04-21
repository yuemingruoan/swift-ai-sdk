# Transport Family Matrix

这份矩阵不是 API 文档的替代品，而是帮宿主快速回答两个实际问题：

1. 当前应该选哪一类 transport family？
2. 哪些配置项是多 family 共用的，哪些是 family-specific 的？

## Family 总览

| Family | 主要类型 | Provider | 协议 | 当前范围 |
| --- | --- | --- | --- | --- |
| 直连 OpenAI HTTP | `OpenAIResponsesRequestBuilder`、`URLSessionOpenAIResponsesTransport` | OpenAI | HTTP JSON | 单次 Responses request/response |
| 直连 OpenAI SSE | `OpenAIResponsesRequestBuilder`、`URLSessionOpenAIResponsesStreamingTransport` | OpenAI | HTTP SSE | 流式 Responses event |
| OpenAI Realtime WebSocket | `OpenAIRealtimeRequestBuilder`、`OpenAIRealtimeWebSocketClient` | OpenAI | WebSocket | Realtime event loop 与 turn execution |
| OpenAI Responses WebSocket | `OpenAIResponsesWebSocketRequestBuilder`、`URLSessionOpenAIResponsesWebSocketTransport` | OpenAI | WebSocket | 通过 WebSocket 拉流的 Responses |
| 直连 Anthropic HTTP | `AnthropicMessagesRequestBuilder`、`URLSessionAnthropicMessagesTransport` | Anthropic | HTTP JSON | Messages request/response 与 tool loop |
| Authenticated OpenAI-compatible HTTP | `OpenAIAuthenticatedResponsesRequestBuilder`、`URLSessionOpenAIAuthenticatedResponsesTransport` | OpenAI-compatible | HTTP JSON | ChatGPT/Codex 风格 authenticated Responses |
| Authenticated OpenAI-compatible SSE | `OpenAIAuthenticatedResponsesRequestBuilder`、`URLSessionOpenAIAuthenticatedResponsesStreamingTransport` | OpenAI-compatible | HTTP SSE | authenticated 流式 Responses |
| Authenticated OpenAI-compatible WebSocket | `OpenAIAuthenticatedResponsesWebSocketRequestBuilder`、`URLSessionOpenAIAuthenticatedResponsesWebSocketTransport` | OpenAI-compatible | WebSocket | authenticated 的 WebSocket Responses |

## 配置矩阵

| 能力 | 直连 OpenAI HTTP/SSE | 直连 Anthropic HTTP | OpenAI Realtime WebSocket | OpenAI Responses WebSocket | Authenticated OpenAI-compatible HTTP/SSE | Authenticated OpenAI-compatible WebSocket |
| --- | --- | --- | --- | --- | --- | --- |
| 共享 `AgentHTTPTransportConfiguration` | 是 | 是 | 否 | 否 | 是 | 只复用 header 相关子集 |
| `timeoutInterval` | 是 | 是 | 否 | 否 | 是 | 否 |
| `retryPolicy` | 是 | 是 | 否 | 否 | 是 | 否 |
| `additionalHeaders` | 是 | 是 | 是，通过 family 自己的配置 | 是，通过 family 自己的配置 | 是 | 是 |
| `userAgent` | 是 | 是 | 是 | 是 | 是 | 是 |
| `requestID` / request header | `X-Request-Id` | `X-Request-Id` | 仅 family-specific | `x-client-request-id` | `X-Request-Id` | `X-Request-Id`，以及可选的 `x-client-request-id` |
| 注入 session / test double | 是 | 是 | 是 | 是 | 是 | 是 |
| compatibility-specific headers | 否 | 否 | 有时有 | 有时有 | 是 | 是 |

## 怎么选 Family

### 适合直连 OpenAI HTTP / SSE 的情况

- 你用的是标准 OpenAI API key
- 你想直接使用最中性的 OpenAI Responses surface
- 你希望完整使用共享 HTTP transport 配置

### 适合 Anthropic HTTP 的情况

- 你今天接的是 Anthropic Messages
- 你要的是 request/response 或 tool-loop
- 你当前不需要 Anthropic streaming

### 适合 authenticated OpenAI-compatible transport 的情况

- 你接的是 ChatGPT/Codex 风格 bearer token 或兼容后端
- 你需要 compatibility transform 和 auth-aware header shaping
- 你同时还希望在 HTTP/SSE 路径上复用共享 timeout/retry/header 配置

### 适合 WebSocket family 的情况

- 你明确需要 WebSocket
- 你接受它的配置面和共享 HTTP config 并不完全一样
- 你愿意自己处理连接生命周期与流式状态

## 各 Family 常见错误面

| Family | 更常见的 SDK-facing 错误 |
| --- | --- |
| HTTP request/response family | `AgentProviderError`、`AgentTransportError`、`AgentDecodingError`，authenticated family 还会常见 `AgentAuthError` |
| SSE family | 在 HTTP 错误之外再加上 `AgentStreamError` |
| Realtime / WebSocket family | `AgentTransportError`、`AgentDecodingError`、`AgentRuntimeError`，以及部分流式投影失败时的 `AgentStreamError` |
| 任何接了文件持久化的宿主流程 | 持久化相关的 `AgentPersistenceError` |

conversion-specific 错误不放进这个矩阵，因为它们描述的是 provider 形状转换，而不是
transport family 的选择问题。

## 当前已知缺口

这份矩阵描述的是仓库现状，不是未来承诺：

- 还没有 Anthropic streaming。
- WebSocket family 还没有和 HTTP family 共用完整 transport config。
- authenticated family 仍然暴露一些共享 transport 配置之外的 compatibility 字段。
- 这份矩阵只聚焦 transport，不替代 README 里的 provider capability matrix。
