# Changelog

All notable changes to this repository will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows semantic versioning for the SwiftPM version surface.

## [Unreleased]

### Changed

- unified tool-loop iteration budget failures under `AgentRuntimeError` instead of provider-specific client error enums
- clarified in the README that conversion-layer failures remain provider-specific while runtime failures use the SDK-facing taxonomy
- documented the concrete SDK-facing error layers and the shared HTTP transport configuration surface in the README and docs reference pages
- extended shared transport configuration coverage into authenticated OpenAI-compatible Responses HTTP/SSE transports and the header-oriented subset of the authenticated WebSocket builder
- removed the stale `OpenAIRealtimeMessageConversionError` surface and kept realtime message-part failures on the shared `AgentDecodingError` path
- added a host-facing error handling cookbook and a transport family matrix in both English and Simplified Chinese
- removed the stale `SDK_IMPROVEMENT_PLAN.md` archive file and added `docs/README.md` as the active documentation index for release preparation

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
