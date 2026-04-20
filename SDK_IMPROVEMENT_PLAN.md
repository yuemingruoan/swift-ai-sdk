# Swift AI SDK Improvement Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current working OpenAI-first infrastructure baseline into a provider-neutral multi-turn SDK with adapter-ready persistence and a second provider implementation.

**Architecture:** Keep `AgentCore` provider-neutral, keep persistence protocol-driven, and add provider adapters and store adapters around those stable contracts. Build outward from the existing one-turn runners instead of replacing them. Each stage should end in a testable, shippable checkpoint.

**Tech Stack:** Swift 6, SwiftPM, Foundation, URLSession, Swift Testing, swift-syntax macros, protocol-based persistence adapters

---

## Current Baseline

Already implemented:

- `AgentCore` message, event, tool, and runner primitives
- `AgentOpenAI` Responses, SSE, Realtime WS, and tool-loop support
- `AgentPersistence` stores plus `RecordingAgentTurnRunner`
- `AgentMacros` tool descriptor macro support
- `OpenAIResponsesExample`

Not implemented yet:

- provider-neutral multi-turn session runtime
- richer tool metadata and middleware hooks
- a SwiftData adapter target
- a disk-backed fallback persistence store
- Anthropic provider support

## Ordered Execution

The tasks below are intentionally sequential. Do not skip ahead. Each one sets up contracts the next one depends on.

### Task 1: Add Provider-Neutral Multi-Turn Session State

**Files:**
- Create: `Sources/AgentCore/Sessions/AgentConversationState.swift`
- Create: `Sources/AgentCore/Sessions/AgentRunContext.swift`
- Create: `Tests/AgentCoreTests/AgentConversationStateTests.swift`
- Modify: `Sources/AgentCore/AgentCore.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AgentCoreTests/AgentConversationStateTests.swift` with tests for:

- creating a conversation state with a session id and empty history
- appending input/output messages after one completed turn
- storing provider continuation metadata without tying it to OpenAI types
- round-tripping the state through `Codable`

Use concrete expectations around:

- `sessionID`
- `messages`
- a generic continuation dictionary such as `[String: String]`

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
swift test --filter AgentConversationStateTests
```

Expected:

- FAIL because `AgentConversationState` and `AgentRunContext` do not exist yet

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/AgentCore/Sessions/AgentConversationState.swift` with a small value type that owns:

- `sessionID: String`
- `messages: [AgentMessage]`
- `continuation: [String: String]`

Create `Sources/AgentCore/Sessions/AgentRunContext.swift` with a value type that owns:

- `session: AgentSession`
- `conversation: AgentConversationState`

Keep both types:

- `Codable`
- `Equatable`
- `Sendable`

Modify `Sources/AgentCore/AgentCore.swift` only if needed to keep module-level documentation aligned with the new runtime responsibility.

- [ ] **Step 4: Run the tests to verify pass**

Run:

```bash
swift test --filter AgentConversationStateTests
```

Expected:

- PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentCore/Sessions/AgentConversationState.swift \
        Sources/AgentCore/Sessions/AgentRunContext.swift \
        Sources/AgentCore/AgentCore.swift \
        Tests/AgentCoreTests/AgentConversationStateTests.swift
git commit -m "feat: add provider-neutral conversation state"
```

### Task 2: Add Session Runner on Top of Turn Runners

**Files:**
- Create: `Sources/AgentCore/Runners/AgentSessionRunner.swift`
- Create: `Tests/AgentCoreTests/AgentSessionRunnerTests.swift`
- Modify: `Sources/AgentCore/Runners/AgentTurnRunner.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AgentCoreTests/AgentSessionRunnerTests.swift` covering:

- running one turn from existing state
- appending new user input into the outgoing turn request
- capturing `.messagesCompleted` output back into conversation history
- preserving previously stored messages across turns

Use a stub `AgentTurnRunner` that emits:

- `.textDelta("...")`
- `.messagesCompleted([...])`

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
swift test --filter AgentSessionRunnerTests
```

Expected:

- FAIL because `AgentSessionRunner` does not exist yet

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/AgentCore/Runners/AgentSessionRunner.swift` that:

- wraps any `AgentTurnRunner`
- accepts an `AgentConversationState`
- prepends stored history to new input before calling the base runner
- captures the final completed messages and returns updated state

Do not add provider-specific logic here.

If needed, extend `AgentTurnRunner.swift` with helper typealiases, but keep the protocol stable.

- [ ] **Step 4: Run the tests to verify pass**

Run:

```bash
swift test --filter AgentSessionRunnerTests
```

Expected:

- PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentCore/Runners/AgentSessionRunner.swift \
        Sources/AgentCore/Runners/AgentTurnRunner.swift \
        Tests/AgentCoreTests/AgentSessionRunnerTests.swift
git commit -m "feat: add session runner on top of turn runners"
```

### Task 3: Extend Tool Metadata and Add Invocation Hooks

**Files:**
- Modify: `Sources/AgentCore/Tools/ToolDescriptor.swift`
- Create: `Sources/AgentCore/Tools/ToolExecutorHook.swift`
- Modify: `Sources/AgentCore/Tools/ToolExecutor.swift`
- Create: `Tests/AgentCoreTests/ToolExecutorHookTests.swift`
- Modify: `Tests/AgentCoreTests/ToolRegistryTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests for:

- `ToolDescriptor` carrying `description`
- `ToolDescriptor` carrying `outputSchema`
- hook invocation before tool execution
- hook invocation after tool execution
- hook invocation when tool execution throws

Use both a local and a remote tool test case.

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
swift test --filter ToolExecutorHookTests
swift test --filter ToolRegistryTests
```

Expected:

- FAIL because the new metadata and hooks are missing

- [ ] **Step 3: Write the minimal implementation**

Update `ToolDescriptor.swift` to add:

- `description: String?`
- `outputSchema: ToolInputSchema?`

Create `ToolExecutorHook.swift` with a protocol for:

- `willInvoke`
- `didInvoke`
- `didFail`

Update `ToolExecutor.swift` so hooks are optional and invoked around both local and remote execution.

Keep hooks observational only in this task. Do not add policy blocking yet.

- [ ] **Step 4: Run the tests to verify pass**

Run:

```bash
swift test --filter ToolExecutorHookTests
swift test --filter ToolRegistryTests
```

Expected:

- PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentCore/Tools/ToolDescriptor.swift \
        Sources/AgentCore/Tools/ToolExecutorHook.swift \
        Sources/AgentCore/Tools/ToolExecutor.swift \
        Tests/AgentCoreTests/ToolExecutorHookTests.swift \
        Tests/AgentCoreTests/ToolRegistryTests.swift
git commit -m "feat: add tool metadata and executor hooks"
```

### Task 4: Add Adapter-Ready Persistence Models for SwiftData Hosts

**Files:**
- Create: `Sources/AgentPersistence/AgentPersistenceRecords.swift`
- Create: `Sources/AgentPersistence/AgentPersistenceMapper.swift`
- Create: `Tests/AgentPersistenceTests/AgentPersistenceMapperTests.swift`
- Modify: `Sources/AgentPersistence/AgentPersistence.swift`

- [ ] **Step 1: Write the failing tests**

Create tests for mapping:

- `AgentSession` to a plain persistence record
- `AgentTurn` to a plain persistence record
- persistence records back to runtime models
- preservation of `sequenceNumber`
- preservation of message parts

These record types must be pure Swift structs, not `SwiftData` models.

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
swift test --filter AgentPersistenceMapperTests
```

Expected:

- FAIL because the record and mapper types do not exist

- [ ] **Step 3: Write the minimal implementation**

Create `AgentPersistenceRecords.swift` with:

- `AgentSessionRecord`
- `AgentTurnRecord`

Create `AgentPersistenceMapper.swift` with conversion functions:

- runtime model to record
- record to runtime model

These record types are the adapter seam SwiftData hosts will wrap in their own target.

- [ ] **Step 4: Run the tests to verify pass**

Run:

```bash
swift test --filter AgentPersistenceMapperTests
```

Expected:

- PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentPersistence/AgentPersistenceRecords.swift \
        Sources/AgentPersistence/AgentPersistenceMapper.swift \
        Sources/AgentPersistence/AgentPersistence.swift \
        Tests/AgentPersistenceTests/AgentPersistenceMapperTests.swift
git commit -m "feat: add adapter-ready persistence record mapping"
```

### Task 5: Add File-Backed Persistence Store

**Files:**
- Create: `Sources/AgentPersistence/FileAgentStore.swift`
- Create: `Tests/AgentPersistenceTests/FileAgentStoreTests.swift`
- Modify: `Sources/AgentPersistence/AgentSessionStore.swift`
- Modify: `Sources/AgentPersistence/AgentTurnStore.swift`

- [ ] **Step 1: Write the failing tests**

Create tests for:

- saving sessions to disk
- appending turns to disk
- reading sessions and turns back after re-instantiating the store
- deleting one session and its turns

Use a temporary directory per test.

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
swift test --filter FileAgentStoreTests
```

Expected:

- FAIL because `FileAgentStore` does not exist

- [ ] **Step 3: Write the minimal implementation**

Create `FileAgentStore.swift` using:

- one JSON file for sessions
- one JSON file for turns

Reuse the same protocol surface as `InMemoryAgentStore`.

Do not add compaction, migrations, or locking beyond what is required for one-process correctness.

- [ ] **Step 4: Run the tests to verify pass**

Run:

```bash
swift test --filter FileAgentStoreTests
```

Expected:

- PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentPersistence/FileAgentStore.swift \
        Sources/AgentPersistence/AgentSessionStore.swift \
        Sources/AgentPersistence/AgentTurnStore.swift \
        Tests/AgentPersistenceTests/FileAgentStoreTests.swift
git commit -m "feat: add file-backed persistence store"
```

### Task 6: Add Anthropic Provider Baseline

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AgentAnthropic/AgentAnthropic.swift`
- Create: `Sources/AgentAnthropic/AnthropicMessagesRequest.swift`
- Create: `Sources/AgentAnthropic/AnthropicMessagesClient.swift`
- Create: `Sources/AgentAnthropic/AnthropicTurnRunner.swift`
- Create: `Tests/AgentAnthropicTests/AnthropicMessagesClientTests.swift`
- Create: `Tests/AgentAnthropicTests/AnthropicTurnRunnerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create tests for:

- converting `AgentMessage` input to Anthropic Messages payloads
- projecting Anthropic message output back into `AgentStreamEvent`
- routing tool use / tool result through the same `ToolExecutor`

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
swift test --filter AnthropicMessagesClientTests
swift test --filter AnthropicTurnRunnerTests
```

Expected:

- FAIL because `AgentAnthropic` target does not exist

- [ ] **Step 3: Write the minimal implementation**

Add `AgentAnthropic` as a new target and implement:

- one-shot Messages request model
- minimal transport/client
- one-turn runner
- tool-loop handling aligned with existing `AgentTurnRunner` conventions

Do not attempt full feature parity with `AgentOpenAI` in this task. Only land the minimum surface needed to validate the core abstractions.

- [ ] **Step 4: Run the tests to verify pass**

Run:

```bash
swift test --filter AnthropicMessagesClientTests
swift test --filter AnthropicTurnRunnerTests
swift test
```

Expected:

- PASS

- [ ] **Step 5: Commit**

```bash
git add Package.swift \
        Sources/AgentAnthropic \
        Tests/AgentAnthropicTests
git commit -m "feat: add anthropic provider baseline"
```

## Self-Review Checklist

Spec coverage:

- multi-turn runtime: covered by Tasks 1 and 2
- richer tool system: covered by Task 3
- SwiftData-friendly persistence without SDK dependency: covered by Task 4
- cross-platform fallback persistence: covered by Task 5
- second provider to validate abstractions: covered by Task 6

Placeholder scan:

- no `TBD`
- no `TODO`
- no references to undefined task outputs

Type consistency:

- `AgentConversationState` and `AgentRunContext` are introduced before `AgentSessionRunner`
- tool metadata changes are isolated before provider expansion depends on them
- persistence record mapping lands before any host-specific SwiftData adapter is considered

## Recommended Execution Order

Execute exactly in this order:

1. Task 1
2. Task 2
3. Task 3
4. Task 4
5. Task 5
6. Task 6

Do not start `AgentAnthropic` before the provider-neutral session and persistence seams are stable.
