# swift-ai-sdk

[English](README.md) | [简体中文](README.zh-CN.md)

一套面向 Apple 平台宿主的 Swift-first AI runtime 基础设施：核心层保持
provider-neutral，上层再叠加不同 provider 的 adapter。

## 为什么做这个 SDK

- 把消息、工具、会话和持久化模型稳定在 provider-neutral 的核心层
- 同时提供高层 `runTurn` 式入口和可直接下潜的底层 request/transport API
- 让宿主可以按需接入 Keychain 之类的平台 adapter，而不把核心层绑死在 Apple 专用框架上

## 当前状态

- `v0.1.0` 已于 2026-04-21 发布，作为首个公开 SwiftPM tag
- `main` 是后续开发线，用于承接 `v0.1.1` 及之后的工作
- 当前还没有既有外部安装用户，因此 `0.x` 阶段允许继续做破坏性 API 调整
- `0.x` 阶段如果发生 breaking change，应在 `CHANGELOG.md` 和 GitHub Release Notes 中明确写清
- 当前仓库已经是偏生产可用的基础设施基线，但还不是面向终端开发者的完整成品 SDK

### 已经具备的能力

- OpenAI Responses 请求/响应、SSE streaming、Realtime turn execution
- Anthropic Messages 请求/响应与 tool loop 执行
- 通过 `AgentConversationState` 和 `AgentSessionRunner` 提供 provider-neutral 多轮状态
- 用一套统一契约执行本地或远程工具
- 内存/文件持久化，以及 recording runner wrapper
- ChatGPT/Codex 风格的 authenticated Responses transport，以及 Apple Keychain token 存储

### 暂未纳入

- 内建的 SwiftData adapter target
- Anthropic streaming 或 Realtime 支持
- 超出观测型 executor hook 的策略/中间件拦截能力
- 更丰富的宿主 adapter 矩阵

### Provider Feature Matrix

| 能力 | OpenAI | Anthropic |
| --- | --- | --- |
| request / response | 已支持 | 已支持 |
| streaming | 已支持，基于 SSE Responses streaming | 暂未支持 |
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

`v0.1.0` 是当前公开 SwiftPM 基线：

```swift
dependencies: [
    .package(
        url: "https://github.com/yuemingruoan/swift-ai-sdk.git",
        from: "0.1.0"
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
- `AnthropicMessagesRequest`、`AnthropicMessagesRequestBuilder`、`URLSessionAnthropicMessagesTransport`
- `OpenAITokenProvider`、`OpenAIAuthenticatedResponsesRequestBuilder` 以及对应的 authenticated transport
- `AgentSessionStore`、`AgentTurnStore`、`FileAgentStore` 与持久化 record mapper

## 示例

- `OpenAIResponsesExample`：最基础的 OpenAI Responses 文本流程
- `OpenAIToolLoopExample`：OpenAI tool loop
- `AnthropicToolLoopExample`：Anthropic tool loop
- `SessionRunnerExample`：provider-neutral 多轮状态
- `PersistenceExample`：持久化 turn 记录
- `Examples/AppleHostExample`：独立 macOS SwiftUI 宿主，串起 Browser OAuth、Keychain、SwiftData 与 tool execution

常用命令：

```bash
swift run OpenAIResponsesExample "Write one sentence about Swift concurrency."
swift run OpenAIToolLoopExample "What is the weather in Paris? Use the tool."
swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
swift run SessionRunnerExample
swift run PersistenceExample
cd Examples/AppleHostExample && swift build --target AppleHostExample
```

## 文档

- 公开 API 已开始补齐符合 Swift 风格的文档注释
- 注释覆盖范围包括高层入口 API，以及底层 builder、request model、transport
- SDK-facing 错误模型现已覆盖 provider、transport、decoding、auth、stream 和 persistence 等失败类别
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
