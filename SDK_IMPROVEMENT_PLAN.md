# SDK Improvement Plan Archive

This file no longer defines the active forward plan for the repository.

- `v0.1.0` shipped on 2026-04-21
- items that were previously tracked here have either already landed or moved
  into the versioned roadmap
- the active roadmap now lives in [ROADMAP.md](ROADMAP.md)

For current release sequencing, version readiness, and known capability gaps,
use `ROADMAP.md` together with `CHANGELOG.md` and `docs/RELEASING.md`.
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
