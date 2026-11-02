#!/usr/bin/env bash
# Recommended repository settings for branch hygiene and security defaults.
set -euo pipefail

REPO_SLUG="${1:-${GITHUB_REPOSITORY:-}}"
if [[ -z "$REPO_SLUG" ]]; then
    echo "usage: $0 owner/repo" >&2
    exit 64
fi

echo "Patching repository settings for ${REPO_SLUG}…"
gh api --method PATCH "repos/${REPO_SLUG}" \
    -f delete_branch_on_merge=true \
    -f allow_auto_merge=false \
    -f allow_merge_commit=true \
    -f allow_squash_merge=true \
    -f allow_rebase_merge=true \
    -F web_commit_signoff_required=false \
    >/dev/null

echo "Done."
