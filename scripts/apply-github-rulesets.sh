#!/usr/bin/env bash
# Apply repository rulesets from .github/rulesets/*.json via the GitHub REST API.
# Requires: gh auth login with repo admin scope.
#
# Usage:
#   GITHUB_REPOSITORY=owner/repo scripts/apply-github-rulesets.sh
#   scripts/apply-github-rulesets.sh owner/repo
set -euo pipefail

REPO_SLUG="${1:-${GITHUB_REPOSITORY:-}}"
if [[ -z "$REPO_SLUG" ]]; then
    echo "usage: $0 owner/repo" >&2
    exit 64
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULESET_DIR="$ROOT/.github/rulesets"

if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI is required" >&2
    exit 1
fi

existing_names() {
    gh api "repos/${REPO_SLUG}/rulesets" --paginate --jq '.[].name' 2>/dev/null || true
}

upsert_ruleset() {
    local file="$1"
    local name
    name="$(jq -r '.name' "$file")"

    local id
    id="$(gh api "repos/${REPO_SLUG}/rulesets" --paginate --jq ".[] | select(.name==\"$name\") | .id" | head -1)"

    if [[ -n "$id" ]]; then
        echo "Updating ruleset \"$name\" (id $id)…"
        gh api --method PUT "repos/${REPO_SLUG}/rulesets/${id}" --input "$file"
    else
        echo "Creating ruleset \"$name\"…"
        gh api --method POST "repos/${REPO_SLUG}/rulesets" --input "$file"
    fi
}

for file in "$RULESET_DIR"/*.json; do
    [[ -f "$file" ]] || continue
    upsert_ruleset "$file"
done

echo "Done. Verify in GitHub → Settings → Rules → Rulesets."
