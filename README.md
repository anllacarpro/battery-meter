# Battery Meter

Native macOS menu bar app that shows **honest battery runtime**, health details macOS hides, and history over time. Read-only — no charge limiting or cloud sync.

**Requires macOS 27 (Tahoe) or later** and a Mac with a built-in battery.

## Install with Homebrew

This repo is a [Homebrew tap](https://docs.brew.sh/Taps). After the first [GitHub release](#releases) is published:

```bash
brew tap anllacarpro/battery-meter https://github.com/anllacarpro/battery-meter.git
brew install --cask battery-meter
```

To upgrade later:

```bash
brew update
brew upgrade --cask battery-meter
```

### Install without tapping (one-off)

```bash
brew install --cask https://raw.githubusercontent.com/anllacarpro/battery-meter/main/Casks/battery-meter.rb
```

Use a release tag in the URL instead of `main` if you want a pinned version.

## Build from source

```bash
git clone https://github.com/anllacarpro/battery-meter.git
cd battery-meter
bash scripts/bundle.sh
open "build/Battery Meter.app"
```

Install to `~/Applications`:

```bash
bash scripts/bundle.sh --install
```

Run tests:

```bash
swift test
```

## Releases

1. Bump [`VERSION`](VERSION) if needed and merge to `main`.
2. Tag: `git tag v0.1.0 && git push origin v0.1.0`
3. GitHub Actions publishes the zip and opens a PR that updates the Homebrew cask `sha256` — merge that PR before telling users to `brew upgrade`.

Local release dry run:

```bash
bash scripts/release.sh
```

## Features

- Menu bar time remaining (smoothed from real power draw)
- Control Center–style popover with health, cycles, and power draw
- Full window with overview, history, health, and settings
- Launch at login (optional)

## License

[MIT](LICENSE)

## Contributing

Issues and pull requests are welcome. Please run `swift test` before opening a PR.

`main` is protected by [repository rulesets](.github/GOVERNANCE.md) (PR + CI required). Release tags `v*` cannot be deleted via ruleset policy.
