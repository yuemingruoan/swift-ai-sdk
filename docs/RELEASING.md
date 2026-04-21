# Releasing swift-ai-sdk

`v0.1.0` was released on 2026-04-21 as the first public SwiftPM tag. This
document now defines how follow-up releases should be prepared and published.

## Version Naming Rules

- Git and GitHub Releases use `vX.Y.Z` tags such as `v0.1.1`
- SwiftPM installation examples keep bare semantic versions such as
  `from: "0.1.0"`
- `CHANGELOG.md` headings should match the Git tag format, for example
  `[v0.1.1]`

## Release Intent

Each release in the `0.x` line is a public infrastructure checkpoint, not a
promise that the SDK is feature-complete. A release should represent:

- a tested provider-neutral core
- documented OpenAI and Anthropic baseline integrations
- documented example entrypoints
- a reviewable changelog and release note surface

## Preconditions

Before creating a tag:

- the release-preparation pull request has been reviewed and approved
- GitHub Actions is green on the merge commit
- `swift test` passes in the root package
- `swift test` passes in `Examples/AppleHostExample`
- `CHANGELOG.md` reflects the release scope
- `README.md` and `README.zh-CN.md` describe installation, current limitations, and the `main` development line accurately
- `ROADMAP.md` reflects the next known milestone after the release being cut

## Release Steps

1. Merge the reviewed release-preparation pull request into `main`.
2. Update `CHANGELOG.md` by moving the release notes from `Unreleased` into a
   dated `vX.Y.Z` section.
3. Verify the merge commit locally:

   ```bash
   swift test
   (cd Examples/AppleHostExample && swift test)
   ```

4. Create the release tag:

   ```bash
   git checkout main
   git pull --ff-only origin main
   git tag v0.1.1
   git push origin v0.1.1
   ```

5. Create the GitHub Release for `v0.1.1` and use the changelog section as the
   release notes.

## Suggested Release Notes Structure

- What this SDK includes today
- What remains intentionally out of scope
- Which examples are the recommended starting points
- Which validation commands were run for the tag
