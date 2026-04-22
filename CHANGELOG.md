# Changelog

All notable changes to this repository will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows semantic versioning for the SwiftPM version surface.

## [Unreleased]

### Changed

- placeholder for post-`v0.2.0` development

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
