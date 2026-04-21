# Releasing swift-ai-sdk

This repository is preparing for its first public SwiftPM release. The initial
tag should be `0.1.0`.

## Release Intent

`0.1.0` is the first public infrastructure release, not a promise that the SDK
is feature-complete. It should represent:

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
- `README.md` and `README.zh-CN.md` describe installation and current limitations accurately

## Release Steps

1. Merge the reviewed release-preparation pull request into `main`.
2. Update `CHANGELOG.md` by moving the release notes from `Unreleased` into a
   dated `0.1.0` section.
3. Verify the merge commit locally:

   ```bash
   swift test
   (cd Examples/AppleHostExample && swift test)
   ```

4. Create the release tag:

   ```bash
   git checkout main
   git pull --ff-only origin main
   git tag 0.1.0
   git push origin 0.1.0
   ```

5. Create the GitHub Release for `0.1.0` and use the changelog section as the
   release notes.

## Suggested Release Notes Structure

- What this SDK includes today
- What remains intentionally out of scope
- Which examples are the recommended starting points
- Which validation commands were run for the tag
