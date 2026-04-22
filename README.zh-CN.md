# swift-ai-sdk

[English](README.md) | [简体中文](README.zh-CN.md)

一套面向 Apple 平台宿主的 Swift-first AI runtime 基础设施：核心层保持
provider-neutral，上层再叠加不同 provider 的 adapter。

## 为什么做这个 SDK

- 把消息、工具、会话和持久化模型稳定在 provider-neutral 的核心层
- 同时提供高层 `runTurn` 式入口和可直接下潜的底层 request/transport API
- 让宿主可以按需接入 Keychain 之类的平台 adapter，而不把核心层绑死在 Apple 专用框架上

## 当前状态

- `v0.2.0` 已于 2026-04-22 发布，作为当前公开 SwiftPM 基线
- `v0.1.0` 仍然是首个公开 SwiftPM tag
- `main` 是后续开发线，用于承接 `v0.3.0` 及之后的工作
- 当前还没有既有外部安装用户，因此 `0.x` 阶段允许继续做破坏性 API 调整
- `0.x` 阶段如果发生 breaking change，应在 `CHANGELOG.md` 和 GitHub Release Notes 中明确写清
- 当前仓库已经是偏生产可用的基础设施基线，但还不是面向终端开发者的完整成品 SDK

### 已经具备的能力

- OpenAI Responses 请求/响应、SSE streaming、Realtime turn execution
- Anthropic Messages 请求/响应、SSE streaming 与 tool loop 执行
- 通过 `AgentConversationState` 和 `AgentSessionRunner` 提供 provider-neutral 多轮状态
- 用一套统一契约执行本地或远程工具
- 已具备 split runtime middleware：model request / response 拦截、tool authorize、message redaction 与结构化 audit event
- 内存/文件持久化，以及 recording runner wrapper
- ChatGPT/Codex 风格的 authenticated Responses transport，以及 Apple Keychain token 存储

### 暂未纳入

- 内建的 SwiftData adapter target
- Anthropic Realtime 支持
- 更丰富的宿主 adapter 矩阵

### Provider Feature Matrix

| 能力 | OpenAI | Anthropic |
| --- | --- | --- |
| request / response | 已支持 | 已支持 |
| streaming | 已支持，基于 SSE Responses streaming | 已支持，基于 SSE Messages streaming |
| realtime | 已支持 | 暂未支持 |
| tool loop | 已支持 | 已支持 |
| auth helpers | 已支持，包含 ChatGPT/Codex 风格 authenticated transport | 暂未支持 |
| transport customization | 已支持，共享 HTTP transport 配置项 | 已支持，共享 HTTP transport 配置项 |

## 模块一览

| 模块 | 作用 | 层级 |
| --- | --- | --- |
| `AgentCore` | 消息、流式事件、会话、工具和 runner 契约 | 高层 + 基础层 |
| `AgentOpenAI` | OpenAI Responses、Realtime、request builder 和 transport | 高层 + 底层 |
| `AgentAnthropic` | Anthropic Messages runner、request builder 和 transport | 高层 + 底层 |
| `AgentOpenAIAuth` | token provider、兼容层 transform、authenticated transport | 底层 + 集成层 |
| `AgentOpenAIAuthApple` | Apple 平台安全 token 存储 | Adapter |
| `AgentPersistence` | session/turn store、持久化 record 和 recording wrapper | 高层 + 底层 |
| `AgentMacros` | `@Tool` 宏支持 | 编写辅助层 |

## 安装

`v0.2.0` 是当前公开 SwiftPM 基线：

```swift
dependencies: [
    .package(
        url: "https://github.com/yuemingruoan/swift-ai-sdk.git",
        from: "0.2.0"
    )
]
```

如果你想直接使用当前 pre-release 基线，也可以跟 `main`，但要接受 API
继续变化：

```swift
dependencies: [
    .package(
        url: "https://github.com/yuemingruoan/swift-ai-sdk.git",
        branch: "main"
    )
]
```

支持平台：

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+
- visionOS 1+

## 快速开始

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

如果你要在 provider 之上维护多轮状态：

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

## 底层 API

高层 runner 只是这个包的一层入口。如果宿主需要自定义 request 结构、直接操纵
transport、或自己接 auth/persistence，这些底层 API 也都是公开且带文档注释的。

常见下潜入口：

- `OpenAIResponseRequest` 和 `OpenAIResponseInputBuilder`
- `OpenAIResponsesRequestBuilder`、`URLSessionOpenAIResponsesTransport`、`URLSessionOpenAIResponsesStreamingTransport`
- `OpenAIRealtimeRequestBuilder` 与 Realtime WebSocket 相关类型
- `AnthropicMessagesRequest`、`AnthropicMessagesRequestBuilder`、`URLSessionAnthropicMessagesTransport`、`URLSessionAnthropicMessagesStreamingTransport`
- `OpenAITokenProvider`、`OpenAIAuthenticatedResponsesRequestBuilder` 以及对应的 authenticated transport
- `AgentSessionStore`、`AgentTurnStore`、`FileAgentStore` 与持久化 record mapper
- `AgentMiddlewareStack` 以及拆分后的 middleware 协议，用于 request/response 拦截、tool authorize、message redaction 与结构化 audit

## SDK-facing 错误分层

这个 SDK 的公开错误面刻意按层拆开，方便宿主区分 provider 失败、transport
失败、decoding 失败、runtime 失败，以及 auth、stream、persistence 等不同问题。

| 层级 | 公开类型 | 典型含义 |
| --- | --- | --- |
| Provider | `AgentProviderError` | provider 返回了合法的 HTTP 响应，但状态码不是 2xx。 |
| Transport | `AgentTransportError` | 请求没有顺利发出、拿到的响应不是合法 `HTTPURLResponse`、连接不可用，或重试已经耗尽。 |
| Decoding | `AgentDecodingError` | request 编码、response JSON 解码，或 provider payload 向 SDK 模型投影时失败。 |
| Runtime | `AgentRuntimeError` | 高层运行时编排失败，例如 tool loop 迭代次数超限，或 middleware 驱动的 tool deny。 |
| Auth | `AgentAuthError` | token 读取/刷新、OAuth 回调、兼容层认证，或安全存储失败。 |
| Stream | `AgentStreamError` | SSE 或其他流式响应在事件/协议层失败。 |
| Persistence | `AgentPersistenceError` | 文件持久化状态无法读成有效数据，或无法写回。 |
| Conversion-specific | `OpenAIConversionError`、`AnthropicConversionError` | provider 形状转换失败，保持 provider-specific，不并入共享 SDK 错误分层。 |

共享错误如果依赖 provider 边界，会直接携带 `AgentProviderID`，宿主可以据此区分
`openai` 和 `anthropic`，而不需要自行解析字符串。

## 共享 HTTP Transport 配置

`AgentHTTPTransportConfiguration` 是 OpenAI 与 Anthropic 直连
`URLSession` HTTP transport 的共用配置面，也覆盖 authenticated 的
OpenAI-compatible Responses HTTP/SSE transport：

- `timeoutInterval`：写入每个生成的 `URLRequest`
- `retryPolicy.maxAttempts`：总尝试次数，包含第一次请求
- `retryPolicy.backoff`：当前支持 `.none` 与 `.constant(milliseconds:)`
- `retryPolicy.retryableStatusCodes`：默认是 `408`、`429`、`500`、`502`、`503`、`504`
- `additionalHeaders`：附加到每个请求上的 header
- `userAgent`：写入 `User-Agent`；如果同时设置了顶层配置的 `userAgent`，这里优先
- `requestID`：写入 `X-Request-Id`

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

同样的共享 transport 配置也适用于
`URLSessionOpenAIResponsesStreamingTransport` 与
`URLSessionOpenAIAuthenticatedResponsesStreamingTransport`。对 authenticated
请求来说，`OpenAIAuthenticatedAPIConfiguration` 现在已经内嵌了这层共享 transport
配置，同时保留 `originator`、`Accept-Language` 这类兼容层特有字段。

OpenAI WebSocket transport 仍然保持独立配置面，但 authenticated 的 WebSocket
builder 已经复用共享 transport 配置里和 header 相关的那部分：`additionalHeaders`、
`userAgent` 与 `requestID`。

## 示例

- `OpenAIResponsesExample`：最基础的 OpenAI Responses 文本流程
- `OpenAIToolLoopExample`：OpenAI tool loop
- `AnthropicToolLoopExample`：Anthropic tool loop，可选 SSE streaming，与 middleware smoke path
- `SessionRunnerExample`：provider-neutral 多轮状态
- `PersistenceExample`：持久化 turn 记录
- `Examples/AppleHostExample`：独立 macOS SwiftUI 宿主，串起 Browser OAuth、Keychain、SwiftData 与 tool execution

常用命令：

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

Anthropic 的 raw response 与 raw streaming event 会保留 provider 返回的
`thinking` block。默认省略它们的是上层 convenience projection；如果宿主想把
thinking 带入投影后的输出，可以显式使用
`AnthropicProjectionOptions.preserveThinking`，或在
`AnthropicTurnRunnerConfiguration(..., projectionOptions: .preserveThinking)`
里打开。

## 文档

- 当前有效文档集合的索引见 [docs/README.md](docs/README.md)
- 公开 API 已开始补齐符合 Swift 风格的文档注释
- 注释覆盖范围包括高层入口 API，以及底层 builder、request model、transport、runtime middleware 和 Anthropic streaming 的 raw/projection 分层边界
- README 现在明确列出了 SDK-facing 错误分层，以及共享 HTTP transport 配置面
- conversion-layer 的失败仍刻意保留为 provider-specific 的 `OpenAIConversionError` 和 `AnthropicConversionError`
- 这两部分的详细说明见 [docs/SDK_ERRORS_AND_TRANSPORT.zh-CN.md](docs/SDK_ERRORS_AND_TRANSPORT.zh-CN.md)
- 面向宿主的错误处理说明见 [docs/ERROR_HANDLING_COOKBOOK.zh-CN.md](docs/ERROR_HANDLING_COOKBOOK.zh-CN.md)
- transport family 对比矩阵见 [docs/TRANSPORT_FAMILY_MATRIX.zh-CN.md](docs/TRANSPORT_FAMILY_MATRIX.zh-CN.md)
- runtime middleware 说明见 [docs/MIDDLEWARE_GUIDE.zh-CN.md](docs/MIDDLEWARE_GUIDE.zh-CN.md)
- 发版治理和 tag 约定见 [docs/RELEASING.md](docs/RELEASING.md)
- 后续版本路线图见 [ROADMAP.md](ROADMAP.md)

## 验证

运行根包测试：

```bash
swift test
```

运行独立 Apple host example 的测试：

```bash
cd Examples/AppleHostExample
swift test
```

GitHub Actions 会通过 `.github/workflows/swift-package.yml` 运行同一套校验。
