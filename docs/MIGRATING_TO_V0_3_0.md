# Migrating To v0.3.0

`v0.3.0` intentionally changes the public module surface.

On `main`, the old mixed provider products have already been replaced with a
two-track surface per provider:

- low-level provider-native API modules
- high-level runtime modules

`AgentCore` is no longer a public product.

## Product Mapping

| Old product | New product(s) | Notes |
| --- | --- | --- |
| `AgentOpenAI` | `OpenAIResponsesAPI`, `OpenAIAgentRuntime` | Split into low-level wire/API surface and high-level runtime surface. |
| `AgentAnthropic` | `AnthropicMessagesAPI`, `AnthropicAgentRuntime` | Split into low-level wire/API surface and high-level runtime surface. |
| `AgentOpenAIAuth` | `OpenAIAuthentication` | Renamed. |
| `AgentOpenAIAuthApple` | `OpenAIAppleAuthentication` | Renamed. |
| `AgentCore` | no public replacement product | Runtime types are surfaced through the public runtime products and `AgentPersistence`. |

## Import Mapping

### OpenAI high-level runtime

Before:

```swift
import AgentOpenAI
```

After:

```swift
import OpenAIAgentRuntime
```

### OpenAI low-level request / transport APIs

Before:

```swift
import AgentOpenAI
```

After:

```swift
import OpenAIResponsesAPI
```

### Anthropic high-level runtime

Before:

```swift
import AgentAnthropic
```

After:

```swift
import AnthropicAgentRuntime
```

### Anthropic low-level request / transport APIs

Before:

```swift
import AgentAnthropic
```

After:

```swift
import AnthropicMessagesAPI
```

### Auth helpers

Before:

```swift
import AgentOpenAIAuth
import AgentOpenAIAuthApple
```

After:

```swift
import OpenAIAuthentication
import OpenAIAppleAuthentication
```

## Typical Migration Shapes

### High-level OpenAI runner

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

### High-level Anthropic runner

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

### Authenticated OpenAI-compatible transports

```swift
import OpenAIAuthentication
import OpenAIResponsesAPI

let transport = URLSessionOpenAIAuthenticatedResponsesTransport(
    configuration: .init(baseURL: baseURL),
    tokenProvider: tokenProvider
)
```

## Notes On Common Types

- `AgentConversationState`, `AgentSessionRunner`, `AgentMessage`,
  `AgentStreamEvent`, `ToolDescriptor`, and `ToolExecutor` are still used by the
  public runtime layer.
- `AgentPersistence` remains a standalone public product and continues to expose
  persistence-oriented types such as `FileAgentStore`, `AgentSessionStore`, and
  `RecordingAgentTurnRunner`.
- Low-level provider-native built-in tools such as OpenAI `web_search` and
  Anthropic `web_search_*` now belong in the API modules, not the runtime
  modules.

## Recommended Update Order

1. Update SwiftPM product dependencies in your package manifest.
2. Replace imports with the new product names.
3. Separate low-level provider-native code from high-level runtime code:
   use `*API` for wire models, builders, transports, and raw streaming events;
   use `*AgentRuntime` for projections, runners, and tool-loop orchestration.
4. Re-run your tests and examples against the new import surface.
