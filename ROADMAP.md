# swift-ai-sdk Roadmap

This roadmap tracks the next public checkpoints after `v0.3.0`.

## Current Baseline

- `v0.3.0` is the current public SwiftPM release
- `v0.1.0` remains the first public SwiftPM release
- `main` is the active development branch for the next public checkpoint
- the repository continues to position itself as production-oriented runtime
  infrastructure rather than a feature-complete end-user SDK

## v0.3.0 Released Scope

Released on 2026-04-22 with:

- public module split into `OpenAIResponsesAPI` / `OpenAIAgentRuntime`,
  `AnthropicMessagesAPI` / `AnthropicAgentRuntime`,
  `OpenAIAuthentication`, and `OpenAIAppleAuthentication`
- `AgentCore` retained as an internal implementation target rather than a
  public product
- migration guides for the new import surface
- provider-native web search request modeling for both OpenAI and Anthropic
- Anthropic raw streaming, server-tool, citation, and web-search helper
  coverage sufficient for provider-native web-search integrations
- opt-in live smoke coverage for authenticated OpenAI transports and
  AppleHostExample send flows, plus a gated Anthropic web-search smoke for
  compatible backends

## v0.4.0 Productization

Focus: reduce host-integration cost after the public module redesign has been
released.

- consider an official SwiftData adapter target
- expand the SwiftUI host example into a richer chat-oriented reference app
- add mock or test providers for offline host development
- expose basic observability signals such as request IDs, latency, retries, and
  failure classification
- consider provider-native convenience helpers on the OpenAI side comparable to
  the Anthropic web-search helper where they add practical value without
  collapsing the low-level API/runtime boundary

## 1.0 Readiness Gates

The repository should not claim `1.0` readiness until all of the following are
true:

- OpenAI and Anthropic both support request/response and streaming
- transport configuration and error taxonomy are stable
- middleware and policy capabilities are available
- persistence has a clear production story beyond the basic file store
- README, changelog, releases, and roadmap stay in sync across versions
- CI remains green for the root package, examples, and `AppleHostExample`
- at least one real host app has been dogfooded on top of the SDK
