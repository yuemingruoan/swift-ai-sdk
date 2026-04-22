# Runtime Middleware 指南

这份文档描述 `swift-ai-sdk` 当前已经存在的 runtime middleware surface，
重点说明它今天能做什么、挂载在哪些层级，以及它和底层 transport 配置之间的边界。

## 设计边界

`AgentMiddlewareStack` 是 runtime 层能力，位于原始 HTTP/SSE transport 和
provider-specific request builder 之上。

当前边界是刻意保持清晰的：

- middleware 负责 model request / response 拦截、tool authorize、message
  redaction 和 audit recording
- `AgentHTTPTransportConfiguration` 只负责 timeout、retry、header、
  user-agent、request ID 这类 HTTP 请求级配置
- `ToolExecutorHook` 继续保留为 observational surface，不被 middleware 替换

如果没有安装任何 middleware，runtime 仍然保持现有零额外行为路径。

## 当前可用的 Middleware 协议

| 协议 | 作用 | 当前层级 |
| --- | --- | --- |
| `AgentModelRequestMiddleware` | 在请求真正发出前查看或改写 provider-neutral request context | 高层 runtime |
| `AgentModelResponseMiddleware` | 在完整响应投影完成后查看或改写 provider-neutral response context | 高层 runtime |
| `AgentToolAuthorizationMiddleware` | 在任何本地 executable 或远程 transport 执行前决定 allow / deny | 工具执行层 |
| `AgentMessageRedactionMiddleware` | 在状态更新或持久化写入前改写完整消息 | session / persistence |
| `AgentAuditMiddleware` | 接收 request、response、authorization、redaction 路径的结构化审计事件 | 全局 runtime |

共享容器是 `AgentMiddlewareStack`。

## 当前接入点

同一套 middleware stack 目前已经接到：

- `ToolExecutor`
- `AgentSessionRunner`
- `RecordingAgentTurnRunner`
- `OpenAIResponsesTurnRunner`
- `OpenAIRealtimeTurnRunner`
- `AnthropicTurnRunner`

这意味着一套 stack 就可以同时治理 provider request/response、tool
allow/deny、session state 更新以及 persistence 发射。

## 当前 Audit Event

audit middleware 当前会收到结构化 `AgentAuditEvent`：

- `modelRequestStarted`
- `modelResponseCompleted`
- `toolAllowed`
- `toolDenied`
- `messagesRedacted`

这些 payload 都是 typed 且 provider-neutral 的。audit 路径面向宿主日志和
决策追踪，不是自由文本接口。

## Tool Authorization 行为

tool authorization 在 `ToolExecutor` 内执行，发生在真正调用下面两类执行器之前：

- 本地 executable
- 远程 transport

授权结果只有两种：

- `.allow`
- `.deny(reason: String?)`

被拒绝时：

- 底层工具不会执行
- runtime 会记录 `toolDenied` audit event
- 调用会以 `AgentRuntimeError.toolCallDenied` 失败

## Message Redaction 行为

当前 redaction 范围是有意收窄的：

- 只处理完整消息
- 不改写流中的 `textDelta`
- 会在 `AgentSessionRunner` 发出 `stateUpdated` 之前运行
- 会在 `RecordingAgentTurnRunner` 持久化或重发 completed turn 之前运行

这样做是为了让第一版 middleware 语义稳定，不把 partial stream mutation 和
persistence policy 混在一起。

## Anthropic Streaming 与 Middleware

Anthropic streaming 现在已经能走与非流式路径同一套高层 middleware stack。

相关公开面包括：

- `URLSessionAnthropicMessagesStreamingTransport`
- `AnthropicMessageStreamEvent`
- `AnthropicMessagesClient(..., streamingTransport: ...)`
- `AnthropicTurnRunnerConfiguration(stream: true)`

高层 turn runner 仍然投影到既有 `AgentStreamEvent` 语义：

- 文本增量映射为 `.textDelta`
- 完整 tool use 映射为 `.toolCall`
- 完整 assistant message 映射为 `.messagesCompleted`

`AgentModelResponseMiddleware` 作用于完整投影后的 message context，而不是 raw
streaming delta。

## 最小示例

```swift
import AnthropicAgentRuntime
import AnthropicMessagesAPI

let middleware = AgentMiddlewareStack(
    toolAuthorization: [
        HostToolPolicy(deniedToolName: "dangerous_tool")
    ],
    audit: [
        HostAuditSink()
    ]
)

let client = AnthropicMessagesClient(
    transport: URLSessionAnthropicMessagesTransport(
        configuration: .init(apiKey: anthropicKey)
    ),
    streamingTransport: URLSessionAnthropicMessagesStreamingTransport(
        configuration: .init(apiKey: anthropicKey)
    )
)

let runner = AnthropicTurnRunner(
    client: client,
    configuration: .init(
        model: "claude-sonnet-4-20250514",
        maxTokens: 1024,
        tools: [tool],
        stream: true
    ),
    executor: executor,
    middleware: middleware
)
```

仓库里也已经带了一个可运行 smoke path：

```bash
ANTHROPIC_STREAM=true EXAMPLE_PRINT_AUDIT=true swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
ANTHROPIC_STREAM=true EXAMPLE_DENY_TOOL=lookup_weather swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
```

## 当前刻意不承诺的内容

这份文档不承诺：

- transport-level 的 URLRequest 改写型 middleware
- 对 partial stream delta 做原位改写
- 脱离共享 SDK taxonomy 的 provider-specific policy surface
- 超出当前 audit event 之外的完整 observability 产品面
