# swift-ai-sdk Roadmap

This roadmap tracks the next public checkpoints after `v0.2.0`.

## Current Baseline

- `v0.2.0` is the current public SwiftPM release
- `v0.1.0` remains the first public SwiftPM release
- `main` is the active development branch after `v0.2.0`
- the repository currently positions itself as provider-neutral runtime
  infrastructure, not a feature-complete end-user SDK

## v0.1.1 Stability

Focus: improve reliability and release governance without widening scope.

- align README, changelog, release guidance, and roadmap with the released
  `v0.1.0` state
- add fixture-based request and response contract tests for OpenAI and
  Anthropic
- add streaming failure-path coverage for SSE truncation, cancellation, parse
  boundaries, and error propagation
- add persistence corruption coverage for invalid JSON, empty files, and
  partially written files
- introduce SDK-facing typed error taxonomy
- introduce shared HTTP transport configuration for OpenAI and Anthropic

Released on 2026-04-22.

## v0.2.0 Provider Parity And Governance

Focus: release the provider-parity and governance baseline without widening
scope into broader productization work.

Released on 2026-04-22 with:

- Anthropic Messages SSE streaming using the existing provider-neutral stream
  event model
- shared runtime middleware with zero extra behavior when the stack is empty
- split middleware surfaces for model request, model response, tool
  authorization, message redaction, and structured audit events
- shared middleware integration across `ToolExecutor`, high-level runners,
  session state updates, and recording persistence wrappers
- explicit raw-versus-projected handling for Anthropic `thinking` blocks so
  low-level interfaces preserve provider payloads while convenience APIs can
  omit or retain thinking by configuration

## v0.3.0 Productization

Focus: reduce host-integration cost for real Apple-platform applications.

- consider an official SwiftData adapter target
- expand the SwiftUI host example into a richer chat-oriented reference app
- add mock or test providers for offline host development
- expose basic observability signals such as request IDs, latency, retries, and
  failure classification

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
