# Releasing Battery Meter

## Checklist

1. Merge the Homebrew/distribution PR to `main` (needs `Casks/battery-meter.rb`, `scripts/release.sh`, and `.github/workflows/release.yml`).
2. Bump [`VERSION`](VERSION) and the cask `version` line when shipping a new version line (for example `0.1.0` → `0.2.0`).
3. Tag and push from `main`:
   ```bash
   git checkout main
   git pull
   git tag v0.1.0
   git push origin v0.1.0
   ```
4. The **Release** workflow builds `Battery-Meter-<version>.zip`, attaches it to the GitHub release, and opens a PR **`chore(homebrew): bump cask to v…`** with the correct `sha256`.
5. Merge that automation PR so the tap on `main` matches the published asset.

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
