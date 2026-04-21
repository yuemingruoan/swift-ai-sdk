# Changelog

All notable changes to this repository will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows semantic versioning for the SwiftPM version surface.

## [Unreleased]

### Added

- placeholder for post-`v0.1.0` development

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
