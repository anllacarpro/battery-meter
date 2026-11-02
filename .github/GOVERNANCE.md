# Repository governance

## Branch rulesets (source of truth)

JSON definitions live in [`.github/rulesets/`](rulesets/):

| Ruleset | Target | Purpose |
|---------|--------|---------|
| **Protect main** | default branch | PRs only, required CI (`test`, `build-app`), no force-push or branch delete |
| **Protect version tags** | `v*` tags | No tag delete or retarget (immutable release tags) |

Apply or refresh after editing JSON:

```bash
scripts/apply-github-rulesets.sh anllacarpro/battery-meter
scripts/apply-github-repo-settings.sh anllacarpro/battery-meter
```

Requires `gh` authenticated as a repo admin.

## CI required checks

The **Protect main** ruleset expects these GitHub Actions check names (from [`.github/workflows/ci.yml`](workflows/ci.yml)):

- `test`
- `build-app`

If you rename jobs, update `protect-main.json` and re-run the apply script.

## Workflow for contributors

1. Branch from `main` (`feat/…`, `fix/…`).
2. Open a PR; wait for CI.
3. Merge via squash or merge commit (all allowed).
4. Releases: tag `v*` on `main` only after the Homebrew cask files are on `main` (see [RELEASING.md](../RELEASING.md)).

## Optional hardening (GitHub UI)

These are not stored in git; enable in **Settings** when you want them:

- **Settings → General → Pull Requests**: allow squash, delete head branches (also set via script).
- **Settings → Code security**: Dependabot alerts, secret scanning (public repos get secret scanning free).
- **Settings → Actions → General**: “Require approval for all outside collaborators” for fork PRs.

## Bypass

Repository admins can bypass rulesets when needed (hotfix). Prefer fixing forward with a follow-up PR.
