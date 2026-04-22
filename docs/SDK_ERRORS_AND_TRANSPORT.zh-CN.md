# SDK 错误分层与共享 Transport 配置

这份文档只描述当前已经存在的公开 SDK surface，聚焦两个宿主侧最常
直接关心的问题：

- SDK-facing 错误分层
- OpenAI / Anthropic 直连 HTTP transport 共用的配置面

它的目标是把现状说清楚，而不是为未来版本提前占位。这里没写到的东西，不应该被当成
当前版本已经承诺的能力。

## 错误分层

SDK 暴露的是一套按层拆开的错误模型，宿主可以先按失败类别分支，再看 provider 或
细节信息，而不是被迫解析 provider-specific 文本。

| 层级 | 公开类型 | 覆盖范围 | 典型例子 |
| --- | --- | --- | --- |
| Provider | `AgentProviderError` | provider 返回了合法 HTTP 响应，但状态不是成功状态。 | OpenAI 或 Anthropic 正常返回 `401`、`429`、`500`。 |
| Transport | `AgentTransportError` | 模型解码之前的请求执行、连接、响应形状问题。 | `URLSession` 报错、没有拿到合法 `HTTPURLResponse`、Realtime 连接未建立、重试耗尽。 |
| Decoding | `AgentDecodingError` | 请求编码、响应解码，或 provider payload 投影为 SDK 模型时失败。 | request body JSON 编码失败、response body JSON 解码失败、response projection 不匹配。 |
| Runtime | `AgentRuntimeError` | 高于原始 transport 的多步运行时编排失败。 | tool loop 迭代预算耗尽、tool call 被 runtime policy 拒绝。 |
| Auth | `AgentAuthError` | token provider、OAuth/browser flow、兼容层认证、安全存储。 | 缺少 refresh token、浏览器回调 state 不匹配、不支持的授权方式、Keychain 操作失败。 |
| Stream | `AgentStreamError` | 请求已经建立后，流式协议本身发生失败。 | SSE event 解码失败、流式 response 状态失败、provider 主动发出 stream server error。 |
| Persistence | `AgentPersistenceError` | 文件持久化读写失败。 | 持久化 JSON 无法解析、session/turn 文件写入失败。 |
| Conversion-specific | `OpenAIConversionError`、`AnthropicConversionError` | 刻意保留为 provider-specific 的形状转换失败。 | 不支持的 message role、不支持的内容块、无效 function call 参数。 |

### 共享错误与 Provider-specific 错误的边界

`Agent*Error` 系列就是 SDK-facing 的共享错误分层。如果失败和 provider 边界有关，
这些错误会携带 `AgentProviderID`，宿主可以直接按 `openai` / `anthropic` 分流，
同时又保留统一的失败类别。

而 conversion 系列错误不一样。它们描述的是 SDK 模型和 provider wire model 之间的
确定性形状不匹配，不是请求执行过程中的暂时性失败。实际处理时，通常更应该把它们
看成集成层 bug 或当前输入暂不支持，而不是可重试的 transport 问题。

### 实际处理建议

- `AgentProviderError`、`AgentTransportError`、`AgentAuthError`，以及很多
  `AgentStreamError`，更像运行时失败，适合连同 request 元数据和重试上下文一起记录。
- `AgentDecodingError`、conversion-specific 错误，以及
  `AgentPersistenceError.invalidPersistedData`，通常意味着宿主输入、持久化数据，或
  provider 合约理解存在问题，应该优先排查数据形状。
- `AgentRuntimeError` 更像编排层 guardrail：底层 transport 可能是健康的，但高层 loop
  已经触发了自身限制。

## 共享 HTTP Transport 配置

`AgentHTTPTransportConfiguration` 是下面三个配置里共用的一层：

- `OpenAIAPIConfiguration.transport`
- `AnthropicAPIConfiguration.transport`
- `OpenAIAuthenticatedAPIConfiguration.transport`

当前这层共享配置只作用于直连 `URLSession` 的 HTTP transport：

- `URLSessionOpenAIResponsesTransport`
- `URLSessionOpenAIResponsesStreamingTransport`
- `URLSessionAnthropicMessagesTransport`
- `URLSessionAnthropicMessagesStreamingTransport`
- `URLSessionOpenAIAuthenticatedResponsesTransport`
- `URLSessionOpenAIAuthenticatedResponsesStreamingTransport`

### 支持的配置项

| 配置项 | 行为 |
| --- | --- |
| `timeoutInterval` | 写入每个生成的 `URLRequest.timeoutInterval`。 |
| `retryPolicy.maxAttempts` | 总尝试次数，包含第一次请求。 |
| `retryPolicy.backoff` | 重试延迟策略。当前公开 case 只有 `.none` 和 `.constant(milliseconds:)`。 |
| `retryPolicy.retryableStatusCodes` | 在映射为 provider error 之前触发重试的状态码。默认是 `408`、`429`、`500`、`502`、`503`、`504`。 |
| `additionalHeaders` | 附加到每个请求上的额外 header。 |
| `userAgent` | 写入 `User-Agent`。如果顶层 provider 配置和 `transport.userAgent` 都设置了值，以 transport 层为准。 |
| `requestID` | 写入 `X-Request-Id`。 |

### 示例

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

### 注入 Session 的边界

上面这些 HTTP transport 都支持注入 session，这样宿主可以传入 ephemeral
`URLSession`、自定义协议实现，或测试替身：

- `URLSessionOpenAIResponsesTransport(..., session: any OpenAIHTTPSession)`
- `URLSessionOpenAIResponsesStreamingTransport(..., session: any OpenAIHTTPLineStreamingSession)`
- `URLSessionAnthropicMessagesTransport(..., session: any AnthropicHTTPSession)`
- `URLSessionAnthropicMessagesStreamingTransport(..., session: any AnthropicHTTPLineStreamingSession)`

authenticated 的 OpenAI-compatible Responses transport 也支持注入 session，
并且现在已经消费同一层共享 transport 配置：

- `URLSessionOpenAIAuthenticatedResponsesTransport(..., session: any OpenAIHTTPSession)`
- `URLSessionOpenAIAuthenticatedResponsesStreamingTransport(..., session: any OpenAIHTTPLineStreamingSession)`

它们对外仍然通过 `OpenAIAuthenticatedAPIConfiguration` 暴露配置，因为兼容层特有的
`originator`、`Accept-Language` 等字段并不适合硬塞进共享 transport 配置。

OpenAI WebSocket transport 仍然保持独立配置面，因为它不是普通 HTTP 请求/响应链路。
不过 authenticated 的 WebSocket builder 已经复用了共享 transport 配置里和 header
相关的那部分：

- `additionalHeaders`
- `userAgent`
- `requestID`

它不会使用 `timeoutInterval` 或 `retryPolicy` 这种 HTTP-only 配置项。

## Middleware 说明

`AgentMiddlewareStack` 位于原始 transport 之上，负责 runtime 层的 model
request / response 拦截、tool authorize、message redaction 和 audit
recording；`AgentHTTPTransportConfiguration` 仍然只描述直连
OpenAI / Anthropic HTTP transport 的共享请求级配置。

## Anthropic Thinking 的分层边界

Anthropic 的原始响应面会保留 provider 返回的 thinking block：

- `AnthropicMessageResponse.content`
- `AnthropicMessageStreamEvent`
- `AnthropicMessagesClient.createMessage(_:)`
- `AnthropicMessagesStreamingTransport.streamMessage(_:)`

真正决定“是否把 thinking 带入 provider-neutral 输出”的，是更高一层的
projection / convenience API：

- `AnthropicMessageResponse.projectedOutput(options:)`
- `AnthropicMessagesClient.createProjectedResponse(_:options:)`
- `AnthropicMessagesClient.projectedResponseEvents(..., projectionOptions:)`
- `AnthropicTurnRunnerConfiguration.projectionOptions`

当前 convenience 默认值是 `AnthropicProjectionOptions.omitThinking`。如果宿主
希望在投影后的输出里保留 thinking，可以显式选择
`AnthropicProjectionOptions.preserveThinking`。

## 这份文档不覆盖什么

这份说明不承诺以下内容：

- 超出当前 request ID 与 user-agent 之外的 observability API
- 再把 authenticated / WebSocket transport 全部压成一个统一 transport 类型
