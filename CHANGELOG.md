# Changelog

All notable changes to this repository will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows semantic versioning for the SwiftPM version surface.

## [Unreleased]

## [v0.3.0] - 2026-04-22

### Added

- the `v0.3.0` public module redesign, exposing `OpenAIResponsesAPI`, `OpenAIAgentRuntime`, `AnthropicMessagesAPI`, `AnthropicAgentRuntime`, `OpenAIAuthentication`, and `OpenAIAppleAuthentication`
- provider-native web search request modeling for OpenAI Responses and Anthropic Messages, aligned with each provider's official built-in tool interface
- raw response and streaming decoding coverage for OpenAI `web_search_call` items and Anthropic `server_tool_use` / `web_search_tool_result` blocks
- Anthropic raw citation decoding, `usage.server_tool_use.web_search_requests`, and `AnthropicMessageResponse.webSearchOutput()` for provider-native web-search result extraction without leaving the low-level API layer
- release-facing migration guides for the `v0.3.0` public import-surface change in both English and Simplified Chinese
- opt-in live smoke coverage for authenticated OpenAI transports and AppleHostExample send flows, plus a gated Anthropic web-search live smoke for backends that support official `web_search_*` server tools

### Changed

- `AgentCore` remains as an internal implementation target and is no longer intended to be consumed as a public package product
- examples, tests, README content, and integration docs now use the split `*API` / `*AgentRuntime` / `OpenAIAuthentication` import surface
- high-level OpenAI and Anthropic projections now ignore provider-built-in web search traces instead of treating them like client-executed function tools
- Anthropic compatibility handling now treats `tool_use(name: "web_search")` as a provider-built-in trace for compatibility backends rather than surfacing it as a host-managed tool call

## [v0.2.0] - 2026-04-22

### Added

- shared runtime middleware in `AgentCore`, including request/response interception, tool authorization, message redaction, and structured audit events
- Anthropic Messages SSE streaming transport, raw streaming event model, projected streaming helper, and turn-runner streaming support
- coverage for middleware behavior, Anthropic streaming transport decoding, Anthropic streaming tool-loop follow-up, and runner-level streaming integration
- release-facing middleware documentation and an Anthropic example smoke path for streaming plus middleware

### Changed

- `ToolExecutor`, `AgentSessionRunner`, `RecordingAgentTurnRunner`, OpenAI turn runners, and Anthropic turn runners now accept the shared `AgentMiddlewareStack`
- provider and transport documentation now reflect Anthropic streaming support, the current middleware surface, and the raw-versus-projected thinking boundary

## [v0.1.1] - 2026-04-22

### Changed

- unified the SDK-facing runtime error taxonomy across auth, keychain, realtime, tool loop, and transport-adjacent orchestration paths
- removed legacy provider-specific runtime error enums while keeping provider-specific conversion failures scoped to dedicated conversion layers
- extended shared transport configuration coverage into authenticated OpenAI-compatible Responses HTTP and SSE transports, and reused the header-oriented subset in the authenticated WebSocket builder
- strengthened contract and transport test coverage for shared transport propagation, retry behavior, and runtime error handling
- added and expanded release-facing documentation for SDK error taxonomy, shared transport configuration, host-facing error handling, transport-family comparison, and active documentation indexing
- removed stale planning and archive documentation that was no longer part of the active release-facing source of truth

## [v0.1.0] - 2026-04-21

### Added

- provider-neutral runtime primitives in `AgentCore` for messages, tools, sessions, and runners
- OpenAI Responses support, SSE streaming support, and Realtime turn execution in `AgentOpenAI`
- Anthropic Messages support and tool-loop execution in `AgentAnthropic`
- authenticated OpenAI-compatible transports plus Apple Keychain token storage adapters
- provider-neutral multi-turn state via `AgentConversationState` and `AgentSessionRunner`
- file-backed and in-memory persistence plus recording wrappers in `AgentPersistence`
- `@Tool` macro support in `AgentMacros`
- runnable package examples and a standalone `AppleHostExample` macOS host app

### Changed

- README documentation now defines `v0.1.0` as the first public baseline and `main` as the continuing development line

### Infrastructure

- GitHub Actions verification for the root Swift package and the standalone `AppleHostExample`
- release governance documentation in `docs/RELEASING.md`
