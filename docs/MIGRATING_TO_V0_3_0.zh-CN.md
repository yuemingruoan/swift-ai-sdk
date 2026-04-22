# 迁移到 v0.3.0

`v0.3.0` 会明确调整公开模块面。

在 `main` 上，旧的“混合 provider 模块”已经拆成每个 provider 各自两条线：

- 底层 provider-native API 模块
- 高层 runtime 模块

`AgentCore` 不再作为公开 product 暴露。

## Product 映射

| 旧 product | 新 product | 说明 |
| --- | --- | --- |
| `AgentOpenAI` | `OpenAIResponsesAPI`、`OpenAIAgentRuntime` | 拆成底层 wire/API 面和高层 runtime 面。 |
| `AgentAnthropic` | `AnthropicMessagesAPI`、`AnthropicAgentRuntime` | 拆成底层 wire/API 面和高层 runtime 面。 |
| `AgentOpenAIAuth` | `OpenAIAuthentication` | 重命名。 |
| `AgentOpenAIAuthApple` | `OpenAIAppleAuthentication` | 重命名。 |
| `AgentCore` | 没有新的公开替代 product | 运行时通用类型通过公开 runtime product 与 `AgentPersistence` 暴露。 |

## Import 映射

### OpenAI 高层 runtime

之前：

```swift
import AgentOpenAI
```

之后：

```swift
import OpenAIAgentRuntime
```

### OpenAI 底层 request / transport API

之前：

```swift
import AgentOpenAI
```

之后：

```swift
import OpenAIResponsesAPI
```

### Anthropic 高层 runtime

之前：

```swift
import AgentAnthropic
```

之后：

```swift
import AnthropicAgentRuntime
```

### Anthropic 底层 request / transport API

之前：

```swift
import AgentAnthropic
```

之后：

```swift
import AnthropicMessagesAPI
```

### Auth 辅助模块

之前：

```swift
import AgentOpenAIAuth
import AgentOpenAIAuthApple
```

之后：

```swift
import OpenAIAuthentication
import OpenAIAppleAuthentication
```

## 典型迁移形状

### 高层 OpenAI runner

```swift
import OpenAIAgentRuntime
import OpenAIResponsesAPI

let transport = URLSessionOpenAIResponsesTransport(
    configuration: .init(apiKey: apiKey)
)
let client = OpenAIResponsesClient(transport: transport)
let runner = OpenAIResponsesTurnRunner(
    client: client,
    configuration: .init(model: "gpt-5.4")
)
```

### 高层 Anthropic runner

```swift
import AnthropicAgentRuntime
import AnthropicMessagesAPI

let transport = URLSessionAnthropicMessagesTransport(
    configuration: .init(apiKey: apiKey)
)
let client = AnthropicMessagesClient(transport: transport)
let runner = AnthropicTurnRunner(
    client: client,
    configuration: .init(model: "claude-opus-4-6", maxTokens: 1024)
)
```

### Authenticated OpenAI-compatible transport

```swift
import OpenAIAuthentication
import OpenAIResponsesAPI

let transport = URLSessionOpenAIAuthenticatedResponsesTransport(
    configuration: .init(baseURL: baseURL),
    tokenProvider: tokenProvider
)
```

## 通用类型说明

- `AgentConversationState`、`AgentSessionRunner`、`AgentMessage`、
  `AgentStreamEvent`、`ToolDescriptor`、`ToolExecutor` 这些运行时通用类型仍然会被
  公开 runtime 层继续使用。
- `AgentPersistence` 仍然是独立公开 product，继续暴露 `FileAgentStore`、
  `AgentSessionStore`、`RecordingAgentTurnRunner` 等持久化类型。
- OpenAI `web_search`、Anthropic `web_search_*` 这类 provider-native built-in
  tools 现在应当归到 API 模块，而不是 runtime 模块。

## 推荐迁移顺序

1. 先更新 SwiftPM manifest 里的 product 依赖。
2. 再把源码里的 imports 替换成新 product 名称。
3. 把底层 provider-native 代码和高层 runtime 代码拆开：
   `*API` 用于 wire model、builder、transport、raw streaming event；
   `*AgentRuntime` 用于 projection、runner 和 tool-loop orchestration。
4. 最后对新的 import surface 重新跑测试和 examples。
