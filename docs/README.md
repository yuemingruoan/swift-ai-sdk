# Documentation Index

This directory contains the active repository documentation for the next public
release line.

## Release Preparation

- [RELEASING.md](RELEASING.md): version naming rules, release preconditions,
  tagging flow, and release note structure
- [../CHANGELOG.md](../CHANGELOG.md): release-scoped change log
- [../ROADMAP.md](../ROADMAP.md): active forward plan after the current public
  baseline

## Integration Guidance

- [SDK_ERRORS_AND_TRANSPORT.md](SDK_ERRORS_AND_TRANSPORT.md): SDK-facing error
  taxonomy and shared transport configuration
- [ERROR_HANDLING_COOKBOOK.md](ERROR_HANDLING_COOKBOOK.md): host-facing error
  handling guidance and recommended branching patterns
- [TRANSPORT_FAMILY_MATRIX.md](TRANSPORT_FAMILY_MATRIX.md): transport-family
  comparison across direct, authenticated, HTTP, SSE, realtime, and WebSocket
  surfaces

## Localized References

- [SDK_ERRORS_AND_TRANSPORT.zh-CN.md](SDK_ERRORS_AND_TRANSPORT.zh-CN.md)
- [ERROR_HANDLING_COOKBOOK.zh-CN.md](ERROR_HANDLING_COOKBOOK.zh-CN.md)
- [TRANSPORT_FAMILY_MATRIX.zh-CN.md](TRANSPORT_FAMILY_MATRIX.zh-CN.md)

## Notes

- `SDK_IMPROVEMENT_PLAN.md` has been removed because it was no longer an active
  source of truth and still contained stale implementation-era content.
- The active release-facing documentation set is now the combination of this
  index, `CHANGELOG.md`, `ROADMAP.md`, and `RELEASING.md`.
