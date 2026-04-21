# swift-ai-sdk

[English](README.md) | [简体中文](README.zh-CN.md)

面向 Apple 平台宿主的 Swift-first AI runtime 基础设施，核心层保持 provider-neutral，上层再叠加不同 provider 的适配实现。

当前仓库主要聚焦七部分：

- `AgentCore`：provider-neutral 的消息、流式事件、工具和 runner 原语
- `AgentAnthropic`：Anthropic Messages 的请求构建、响应投影和单轮 runner 支持
- `AgentOpenAI`：OpenAI Responses、SSE streaming 和 Realtime WebSocket 集成
- `AgentOpenAIAuth`：bearer token provider、ChatGPT/Codex 兼容 Responses transport，以及第三方兼容 profile
- `AgentOpenAIAuthApple`：构建在 `AgentOpenAIAuth` 之上的 Apple 专用安全存储适配层
- `AgentPersistence`：持久化协议、内存与文件存储、record mapper，以及 recording runner wrapper
- `AgentMacros`：通过 `@Tool` 宏生成 `ToolDescriptor` 元数据

整个 SDK 以对 SwiftData 友好为目标，但本身不导入也不依赖 `SwiftData`。持久化始终隔离在协议后面，这样宿主可以在自己的 target 中提供 SwiftData-backed adapter，而不会让 SDK 被 Apple 框架绑定死。

## 状态

当前仓库已经是可用的基础设施基线，但还不是一个打磨完成的公开 SDK。现在已经能做到：

- 发起单轮 OpenAI Responses 请求
- 通过 SSE 流式消费 OpenAI Responses
- 运行单轮 OpenAI Realtime WebSocket 会话
- 发起单轮 Anthropic Messages 请求
- 通过一套统一契约注册本地或远程工具
- 在 OpenAI Responses、OpenAI Realtime 和 Anthropic Messages 流程里自动完成 tool call 解析
- 通过协议式 store 持久化已完成的 turn
- 在 turn runner 之上维护 provider-neutral 的多轮会话状态
- 通过带元数据的 descriptor 和 executor hook 观测工具执行过程

当前还没有刻意纳入的内容：

- 内建的 SwiftData adapter target
- Anthropic streaming 或 Realtime 支持
- 超出观测型 executor hook 的策略/中间件拦截能力
- 更丰富的 provider 示例和宿主 adapter

## 包结构

```text
Sources/
  AgentCore/
  AgentAnthropic/
  AgentOpenAI/
  AgentOpenAIAuth/
  AgentOpenAIAuthApple/
  AgentPersistence/
  AgentMacros/
  AgentMacrosPlugin/

Examples/
  ExampleSupport/
  AppleHostExample/
  OpenAIResponsesExample/
  OpenAIToolLoopExample/
  AnthropicToolLoopExample/
  SessionRunnerExample/
  PersistenceExample/

Tests/
  AgentCoreTests/
  AgentAnthropicTests/
  AgentOpenAITests/
  AgentPersistenceTests/
  AgentMacrosTests/
```

## Products

定义见 [Package.swift](Package.swift)：

- `AgentCore`
- `AgentAnthropic`
- `AgentOpenAI`
- `AgentOpenAIAuth`
- `AgentOpenAIAuthApple`
- `AgentPersistence`
- `AgentMacros`
- `OpenAIResponsesExample`
- `OpenAIToolLoopExample`
- `AnthropicToolLoopExample`
- `SessionRunnerExample`
- `PersistenceExample`

支持平台：

- macOS 14+
- iOS 17+
- tvOS 17+
- watchOS 10+
- visionOS 1+

## 核心概念

### 消息与事件

`AgentCore` 暴露的是 provider-neutral 的 runtime 表面：

- `AgentMessage`
- `MessagePart`
- `AgentStreamEvent`
- `AgentConversationState`
- `AgentSessionStreamEvent`
- `AgentTurn`
- `AgentSession`
- `AgentTurnRunner`
- `AgentSessionRunner`

当前最重要的事件类型有：

- `.textDelta(String)`
- `.toolCall(AgentToolCall)`
- `.messagesCompleted([AgentMessage])`
- `.turnCompleted(AgentTurn)`

### 工具

工具通过 `ToolDescriptor` 描述，通过 `ToolExecutor` 执行。

同一套调用模型同时覆盖：

- 本地工具：`LocalToolExecutable`
- 远程工具：`RemoteToolTransport`

现在的 descriptor 还可以携带：

- `description`
- `inputSchema`
- `outputSchema`

工具执行过程还可以通过 `ToolExecutorHook` 观测：

- `willInvoke`
- `didInvoke`
- `didFail`

这样 provider 层就只需要关心 schema 转换和 tool loop 控制，而不用掺杂宿主专属的执行细节。

### 持久化

持久化保持在协议后面：

- `AgentSessionStore`
- `AgentTurnStore`

当前内建实现包括：

- `InMemoryAgentStore`
- `FileAgentStore`
- `AgentSessionRecord`
- `AgentTurnRecord`
- `AgentPersistenceMapper`
- `RecordingAgentTurnRunner`

`RecordingAgentTurnRunner` 会包裹任意 `AgentTurnRunner`，把完成的 turn 落到持久层，并在末尾补发一个 `.turnCompleted(...)` 事件，事件里带的是已持久化后的 turn。

`FileAgentStore` 会把 session 和 turn 以 JSON-backed record 的形式写到磁盘，并在初始化时重新加载。这样宿主即使不接数据库或平台专属框架，也能拿到一个轻量的跨平台 fallback store。

## Anthropic 能力面

已实现的组件：

- `AnthropicMessagesRequest`
- `AnthropicMessagesRequestBuilder`
- `AnthropicMessagesClient`
- `URLSessionAnthropicMessagesTransport`
- `AnthropicTurnRunner`

当前支持的能力：

- 把 `AgentMessage` 输入转换成 Anthropic Messages 请求
- 把 Anthropic assistant 文本和 `tool_use` block 投影回 `AgentStreamEvent`
- 在 Messages 流程里自动完成 client-side tool execution loop
- 复用和其他 provider 相同的 `ToolExecutor` 契约

## OpenAI 能力面

### Responses

已实现的组件：

- `OpenAIResponseRequest`
- `OpenAIResponsesClient`
- `URLSessionOpenAIResponsesTransport`
- `URLSessionOpenAIResponsesStreamingTransport`
- `OpenAIResponsesTurnRunner`

当前支持的能力：

- 结构化请求构建
- 将 `ToolDescriptor` 转成 OpenAI function tool
- 非流式和流式结果投影到 `AgentStreamEvent`
- Responses 流程中的自动 tool execution loop

### Realtime

已实现的组件：

- `OpenAIRealtimeWebSocketClient`
- `OpenAIRealtimeRequestBuilder`
- `OpenAIRealtimeSessionUpdateEvent`
- `OpenAIRealtimeConversationItemCreateEvent`
- `OpenAIRealtimeResponseCreateEvent`
- `OpenAIRealtimeTurnRunner`

当前支持的能力：

- 类型化的 session update
- 发送 user message
- 发送结构化 function call output
- Realtime 流程中的自动 tool execution loop
- 回投到 `AgentStreamEvent`

### Auth 与兼容层

已实现的组件：

- `OpenAIAuthTokens`
- `OpenAITokenProvider`
- `OpenAIExternalTokenProvider`
- `OpenAITokenStore`
- `OpenAITokenRefresher`
- `OpenAIManagedTokenProvider`
- `OpenAIOAuthMethod`
- `OpenAIOAuthSession`
- `OpenAIOAuthFlow`
- `OpenAIChatGPTOAuthConfiguration`
- `OpenAIChatGPTBrowserFlow`
- `OpenAIChatGPTDeviceCodeFlow`
- `OpenAIChatGPTTokenRefresher`
- `OpenAICompatibilityProfile`
- `OpenAIChatGPTRequestTransform`
- `OpenAIAuthenticatedResponsesRequestBuilder`
- `URLSessionOpenAIAuthenticatedResponsesTransport`
- `URLSessionOpenAIAuthenticatedResponsesStreamingTransport`

Apple 适配层：

- `AgentOpenAIAuthApple` 中的 `KeychainOpenAITokenStore`

当前支持的能力：

- 通过 provider 协议接收调用方自行提供的 bearer token
- 通过 `OpenAIManagedTokenProvider` 在 store 之上完成 token 读取与 refresh 编排，
  但存储本身仍保持为协议边界
- 直接生成 ChatGPT/Codex browser 登录链接并在回调后完成 code exchange
- 直接对接 `auth.openai.com` 的 ChatGPT/Codex device-code 登录
- 为 `/backend-api/codex/responses` 构造 ChatGPT/Codex 兼容请求
- 通过 `OpenAITokenProvider.refreshTokens(...)` 提供一次性 401 refresh hook
- 直接对接 `auth.openai.com/oauth/token` 的 OAuth refresh-token exchange
- 为官方 OpenAI、`new-api`、`sub2api` 风格 provider 提供兼容 profile

当前刻意未实现：

- 内置的浏览器唤起 UX 或本地 callback server
- 直接放进共享 auth 层里的跨平台持久化 token store 适配器

存储适配器被刻意排除在核心运行时之外。以 Apple 平台为例，安全保存 token
通常应该走 Keychain 这类专用密码存储 API，但这不是跨平台能力，所以这类实现应
该放在单独的 adapter layer，而不是放进 `AgentCore` 或共享的 auth primitives。
这个仓库现在已经通过 `AgentOpenAIAuthApple` 显式体现了这层拆分。

## 示例

现在仓库里不再只有一个薄示例，而是一组覆盖不同能力面的 example matrix：

- `OpenAIResponsesExample`：最基础的 OpenAI Responses 流式文本示例
- `OpenAIToolLoopExample`：OpenAI Responses + `ToolExecutor` + 可见的 tool loop
- `AnthropicToolLoopExample`：Anthropic Messages + `ToolExecutor` + 可见的 tool loop
- `SessionRunnerExample`：离线演示 `AgentSessionRunner` 和 `AgentConversationState`
- `PersistenceExample`：离线演示 `RecordingAgentTurnRunner` 和 `FileAgentStore`
- `Examples/AppleHostExample`：独立的 macOS SwiftUI SwiftPM 项目，串起 Browser OAuth、Keychain token 存储、SwiftData 会话持久化、tool loop 执行与多轮状态恢复

构建任意一个示例：

```bash
swift build --target OpenAIToolLoopExample
```

常见运行方式：

```bash
OPENAI_API_KEY=sk-... swift run OpenAIResponsesExample "Write one sentence about Swift concurrency."
OPENAI_API_KEY=sk-... swift run OpenAIToolLoopExample "What is the weather in Paris? Use the tool."
OPENAI_ACCESS_TOKEN=eyJ... OPENAI_CHATGPT_ACCOUNT_ID=acc_... swift run OpenAIResponsesExample "Say hello"
OPENAI_ACCESS_TOKEN=eyJ... OPENAI_CHATGPT_ACCOUNT_ID=acc_... swift run OpenAIToolLoopExample "What is the weather in Paris? Use the tool."
ANTHROPIC_API_KEY=sk-ant-... swift run AnthropicToolLoopExample "What is the weather in Paris? Use the tool."
OPENAI_API_KEY=sk-... OPENAI_BASE_URL=https://your-openai-compatible-host/v1 swift run OpenAIToolLoopExample
OPENAI_API_KEY=sk-... OPENAI_BASE_URL=https://your-openai-compatible-host/v1 OPENAI_RESPONSES_FOLLOW_UP_STRATEGY=replay-input swift run OpenAIToolLoopExample
ANTHROPIC_API_KEY=sk-ant-... ANTHROPIC_BASE_URL=https://your-anthropic-compatible-host/v1 swift run AnthropicToolLoopExample
swift run SessionRunnerExample
swift run PersistenceExample
```

独立的 Apple 宿主示例需要在它自己的项目目录里构建：

```bash
cd Examples/AppleHostExample
swift build --target AppleHostExample
```

可选环境变量：

- `OPENAI_API_KEY`
- `OPENAI_ACCESS_TOKEN`
- `OPENAI_MODEL`，默认值是 `gpt-5.4`
- `OPENAI_BASE_URL`，默认值是 `https://api.openai.com/v1`
- `OPENAI_RESPONSES_FOLLOW_UP_STRATEGY`，可选 `auto`、`previous-response-id`、`replay-input`
- `OPENAI_CHATGPT_ACCOUNT_ID`
- `OPENAI_CHATGPT_PLAN_TYPE`
- `OPENAI_COMPAT_PROFILE`，可选 `auto`、`openai`、`newapi`、`sub2api`、`chatgpt-codex-oauth`
- `ANTHROPIC_API_KEY`
- `ANTHROPIC_MODEL`，默认值是 `claude-sonnet-4-20250514`
- `ANTHROPIC_BASE_URL`，默认值是 `https://api.anthropic.com/v1`
- `ANTHROPIC_VERSION`，默认值是 `2023-06-01`

## 最小用法

### 单轮 OpenAI Responses runner

```swift
import AgentCore
import AgentOpenAI

let transport = URLSessionOpenAIResponsesTransport(
    configuration: .init(
        apiKey: apiKey,
        baseURL: URL(string: "https://api.openai.com/v1")!
    )
)
let streamingTransport = URLSessionOpenAIResponsesStreamingTransport(
    configuration: .init(
        apiKey: apiKey,
        baseURL: URL(string: "https://api.openai.com/v1")!
    )
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

for try await event in try runner.runTurn(input: [.userText("hello")]) {
    print(event)
}
```

### 单轮 Anthropic Messages runner

```swift
import AgentCore
import AgentAnthropic

let transport = URLSessionAnthropicMessagesTransport(
    configuration: .init(
        apiKey: apiKey,
        baseURL: URL(string: "https://api.anthropic.com/v1")!,
        version: "2023-06-01"
    )
)
let client = AnthropicMessagesClient(transport: transport)

let runner = AnthropicTurnRunner(
    client: client,
    configuration: .init(
        model: "claude-sonnet-4-20250514",
        maxTokens: 1024
    )
)

for try await event in try runner.runTurn(input: [.userText("hello")]) {
    print(event)
}
```

如果你接的是第三方兼容 provider，把 `baseURL` 指到对方暴露兼容 API 的根路径即可。`OpenAIToolLoopExample` 在检测到 `OPENAI_BASE_URL` 不是官方 OpenAI 主机时，会默认把 follow-up 模式切到 `replay-input`，因为有些兼容网关虽然实现了 `/responses`，但并没有正确支持 `previous_response_id` 的续传。你也可以通过 `OPENAI_RESPONSES_FOLLOW_UP_STRATEGY` 手动覆盖这个行为。

如果你要接 ChatGPT/Codex 风格的 bearer auth，可以使用 `AgentOpenAIAuth` 和 token provider。对于“调用方已经拿到本地 token”的场景，`OpenAIExternalTokenProvider` 是最薄的一层；如果宿主已经有自己的持久化方式，也可以把 `OpenAIManagedTokenProvider` 和自定义 `OpenAITokenStore`、`OpenAITokenRefresher` 组合起来，由 SDK 负责 refresh 编排，或者直接复用 `OpenAIChatGPTTokenRefresher` 对接官方 ChatGPT OAuth refresh 流程。SDK 现在也内置了 `OpenAIChatGPTBrowserFlow` 和 `OpenAIChatGPTDeviceCodeFlow`，对齐官方 Codex 客户端使用的两种登录形态。对于 browser 登录，SDK 只负责生成授权链接，以及在宿主收到 callback URL 之后完成 code exchange；真正打开浏览器和接收本地回调仍由宿主侧组件负责。在 Apple 平台上，`AgentOpenAIAuthApple` 额外提供了 `KeychainOpenAITokenStore` 作为平台专用的安全存储适配器。

### 在 turn runner 之上维护 provider-neutral 会话状态

```swift
import AgentCore

let sessionRunner = AgentSessionRunner(base: runner)
let state = AgentConversationState(sessionID: "session-1")

for try await event in try sessionRunner.runTurn(
    state: state,
    input: [.userText("hello again")]
) {
    print(event)
}
```

### 记录完成的 turn

```swift
import AgentCore
import AgentOpenAI
import AgentPersistence

let store = InMemoryAgentStore()
let recordedRunner = RecordingAgentTurnRunner(
    base: runner,
    session: .init(id: "session-1"),
    sessionStore: store,
    turnStore: store
)
```

### 文件持久化

```swift
import AgentPersistence

let store = try FileAgentStore(
    directoryURL: URL(fileURLWithPath: "/tmp/swift-ai-sdk-store", isDirectory: true)
)
```

## 测试

运行全量测试：

```bash
swift test
```

关键测试分组：

- `AgentCoreTests`
- `AgentAnthropicTests`
- `AgentOpenAITests`
- `AgentPersistenceTests`
- `AgentMacrosTests`

## 设计约束

当前实现遵循这些约束：

- Swift-first 的值类型是事实来源
- provider-specific 的请求模型只是 core type 之上的 adapter
- 持久化保持协议驱动和跨平台
- SwiftData 支持应作为 adapter target 引入，而不是硬依赖
- 本地和远程工具从第一天起就共享同一套调用契约

## 下一步

有序实现路线仍然写在 [SDK_IMPROVEMENT_PLAN.md](SDK_IMPROVEMENT_PLAN.md) 里，不过其中的核心里程碑现在都已经在代码中落地。接下来更值得推进的方向，大概率是 examples、docs、更多宿主 adapter，或者更深入的 provider 覆盖，而不是继续补基础脚手架。
