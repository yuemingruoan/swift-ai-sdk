# 错误处理 Cookbook

这份说明把 SDK 的错误分层进一步翻译成宿主侧可执行的处理策略。它不是 API 文档的替代品，
也不是 `docs/SDK_ERRORS_AND_TRANSPORT.zh-CN.md` 的重复版本；重点是当某类错误出现后，
宿主通常下一步应该怎么做。

## 快速分诊表

| 错误类型 | 典型含义 | 是否建议重试 | 建议记录什么 | 宿主动作 |
| --- | --- | --- | --- | --- |
| `AgentProviderError` | provider 正常返回了响应，但不是成功状态。 | 有时建议。`429`、`500`、`502`、`503`、`504` 通常可重试；持续性的 `4xx` 往往不该盲目重试。 | provider、状态码、request ID、model、endpoint family。 | 套产品层重试策略，对限流做退避，对 provider 明确失败给出用户可理解提示。 |
| `AgentTransportError` | 请求没能正常完成，或没有拿到合法 HTTP/WebSocket 状态。 | 通常可以，如果看起来是暂时性问题。 | provider、request ID、transport 路径、底层 description。 | 对幂等操作做有限重试，或把 UI 切到离线/重连状态。 |
| `AgentDecodingError` | SDK 无法编码请求，或无法解码/投影 provider payload。 | 通常不建议。 | provider、操作类型、model、request ID、decode/projection 描述。 | 把它当成集成层或合约层问题，检查输入形状、持久化数据和 provider 返回。 |
| `AgentRuntimeError` | 高层编排失败，但底层 transport 本身可能是健康的。 | 一般不自动重试。 | provider、guardrail 值、session/turn 上下文。 | 调整宿主策略、tool loop 限制，或修 prompt / tool 设计。 |
| `AgentAuthError` | token、OAuth callback、兼容层认证或安全存储失败。 | 取决于子类型。 | auth 方法、provider、必要的 account/session 标识。 | 重新登录、刷新 token、提示用户处理，或暴露安全存储诊断。 |
| `AgentStreamError` | 请求已建立后，流式协议本身失败。 | 有时建议。 | provider、request ID、event 类型、stream status / error 字段。 | 重连，或在宿主支持时降级到非流式。 |
| `AgentPersistenceError` | 持久化状态无法安全读取或写入。 | `invalidPersistedData` 一般不该自动重试；短暂写入失败可能可以。 | 文件名、session 标识、操作类型。 | 停止静默覆盖，保留原文件，并给出恢复/重建选项。 |
| `OpenAIConversionError`、`AnthropicConversionError` | 确定性的 provider 形状转换失败。 | 不建议。 | 操作类型、问题 role/part/call ID。 | 当成不支持的宿主输入或 SDK/provider 合约 bug。 |

## 推荐的分支方式

宿主应该先按失败类别分流，而不是先解析 provider-specific 文本。一个常见写法是：

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

conversion-specific 错误刻意没有并进共享 taxonomy。它们更适合在构造 provider request
或投影 provider payload 的那一层单独捕获。

## 按类别的处理建议

### `AgentProviderError`

可以先按 `statusCode` 分层处理：

- `429`：退避，并考虑给出限流提示。
- `500`、`502`、`503`、`504`：更像暂时性服务失败；如果操作可重复，可有限重试。
- `400`、`404`：更多是请求结构、model/path、宿主配置问题；不应该盲目重试。
- `401`、`403`：通常更接近 auth/config 问题，而不是普通 provider 重试问题。

### `AgentTransportError`

这类错误描述的是执行和连接，不是模型语义本身。

常见宿主响应：

- 对幂等请求做一次或少量有界重试
- 在 UI 里呈现离线/重连状态
- 日志里带上 request ID、provider、transport family

`notConnected(provider:)` 在 realtime 场景里通常意味着宿主没连上，或断开得太早，
而不是模型请求本身有问题。

### `AgentDecodingError`

默认策略是不自动重试，先定位原因。

先问几个问题：

- 宿主有没有发送 SDK 当前不支持的 message part 或 role？
- 持久化数据是不是已经漂移出当前 shape？
- provider 返回格式是不是发生了变化？

如果是 `requestEncoding`，优先检查宿主侧输入；如果是 `responseBody` 或
`responseProjection`，优先检查 provider payload capture、fixture，以及最近的
provider 合约变化。

### `AgentRuntimeError`

当前公开的 runtime guardrail 主要是：

- `toolCallLimitExceeded(provider:maxIterations:)`

这更像宿主策略失败，而不是 transport 失败。常见处理方式：

- 只有在 loop 明确可控的前提下，才提高 iteration budget
- 优化 tool 描述或 prompt，让模型更快收敛
- 在 UI 或日志里把 repeated tool loop 清楚展示出来

### `AgentAuthError`

auth 错误建议按子类型再拆：

- `missingCredentials`、`refreshUnsupported`、`unauthorized`：通常要重新认证、
  改 token 来源，或给出用户级恢复路径。
- `stateMismatch`、`missingAuthorizationCode`、`callbackError`、
  `unknownAuthorizationSession`：更像 OAuth/browser flow 的状态管理失败。
- `secureStorageFailure`：日志里保留底层状态码，并给出存储层诊断。
- `invalidStoredCredentials`：把已存 token 当成损坏或过期处理，不要继续静默信任。

### `AgentStreamError`

流式错误适合做优雅降级：

- 宿主支持的话，重试一次，或降级到非流式
- 记录 request ID 与 stream event 上下文
- 如果失败发生在 terminal event 之前，不要把部分输出误标为完成结果

### `AgentPersistenceError`

对 `invalidPersistedData`，更安全的默认行为是：

- 显式失败
- 保留原文件
- 让用户选择修复、重建或导出，而不是静默覆盖

写入失败时，也应该把文件名和操作上下文带进日志；不要在写入失败后继续向用户声称
“已经保存成功”。

## 日志建议

日志尽量结构化，而不是堆长文本：

- 错误类别
- provider
- request ID（如果有）
- model
- endpoint family 或 transport family
- session / turn 标识
- retry attempt 次数
- 必要且安全的 auth/session 元数据

不要记录原始 token、完整敏感 prompt，或未脱敏的持久化用户数据。

## 建议的 UI 映射

| 错误类别 | 建议对用户的表达 |
| --- | --- |
| Provider / Transport / Stream | 暂时性的服务或连接问题。 |
| Decoding / Conversion-specific | 不支持的输入，或内部兼容性问题。 |
| Runtime | tool loop 或运行时编排触发了限制。 |
| Auth | 登录、token 或权限问题。 |
| Persistence | 本地保存/读取问题，需要用户介入。 |

## 这份文档不规定什么

这份 cookbook 不规定：

- 每个产品一定要用的重试次数
- 遥测/埋点 schema 设计
- provider-specific 的 moderation / abuse handling
- 现在已经存在的 runtime middleware / policy 行为，例如通过 `AgentRuntimeError` 暴露的 tool deny
