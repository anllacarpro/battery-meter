# Releasing Battery Meter

## How a release happens

Releases are automated by [release-please](https://github.com/googleapis/release-please-action) and need [Conventional Commits](https://www.conventionalcommits.org) on `main`.

1. Merge normal PRs to `main`. `feat:` bumps the minor version, `fix:` the patch, and `feat!:` or a `BREAKING CHANGE:` footer the major.
2. release-please keeps a PR titled **`chore(main): release X.Y.Z`** open. It updates [`VERSION`](VERSION) and `CHANGELOG.md`.
3. Merge that PR when you want to ship. release-please creates the tag and the GitHub release.
4. The **Release** workflow builds `Battery-Meter-<version>.zip`, attaches it to the release, and opens a PR **`chore(homebrew): bump cask to v…`** with the correct `sha256`.
5. Merge that PR so the tap on `main` matches the published asset.

One-time setting: **Settings → Actions → General → Workflow permissions** must allow "Read and write permissions" and "Allow GitHub Actions to create and approve pull requests".

Manual fallback: pushing a `v*` tag from `main` runs the same Release workflow.

Local dry run (optional):

```bash
bash scripts/release.sh <version>
```

## Publishing the tap

Users need at least one GitHub release whose zip URL matches the cask `url` line. Until that exists, `brew install --cask` will fail on download.

Optional: submit to [homebrew-cask](https://github.com/Homebrew/homebrew-cask) once the project meets their [acceptance criteria](https://docs.brew.sh/Acceptable-Formulae) (notability, stable releases).

## Repository visibility

Set the GitHub repository to **Public** under Settings → General → Danger zone.

Add a short **Description** and topics (`macos`, `swift`, `battery`, `menu-bar`) on the repo home page for discoverability.
