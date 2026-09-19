#!/usr/bin/env bash
# check-source-versions.sh — does each catalogue entry's declared version match
# the version its source repository actually publishes?
#
# This is the only check in this repository that needs the network, and it is a
# separate script for exactly that reason: it can fail for a cause that has
# nothing to do with the manifest. This catalogue repo is PUBLIC and the plugins
# it lists are PRIVATE, so a workflow's default GITHUB_TOKEN cannot read them.
# Run unauthenticated it does not find "no problems" — it finds nothing, and it
# says so.
#
#   ./.github/scripts/check-source-versions.sh            # every plugin
#   ./.github/scripts/check-source-versions.sh crbiz-pm   # one
#
# Exit 0  every plugin was looked up and every version matched
# Exit 1  at least one version disagrees with its source repository
# Exit 2  at least one plugin could not be looked up (no credentials, no access,
#         no plugin.json) and nothing mismatched
#
# 2 is not 0. "I looked and found nothing wrong" and "I could not look" are
# different answers; a gate that conflates them reports success while blind.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/.claude-plugin/marketplace.json"
ONLY="${1:-}"

command -v jq >/dev/null || { echo "jq is required but not installed." >&2; exit 2; }
[[ -f "$MANIFEST" ]] || { echo "Manifest not found: $MANIFEST" >&2; exit 2; }

matched=0 mismatched=0 blind=0

# Print the source repo's plugin.json, or nothing if it cannot be read.
fetch_plugin_json() {
  local slug="$1"
  command -v gh >/dev/null || return 1
  gh api "repos/$slug/contents/.claude-plugin/plugin.json" \
    --jq '.content' 2>/dev/null | base64 -d 2>/dev/null
}

while IFS=$'\t' read -r name declared url; do
  [[ -n "$ONLY" && "$name" != "$ONLY" ]] && continue

  if [[ -z "$url" || "$url" == "null" ]]; then
    echo "  ?  $name — no git source URL in the manifest; cannot look"
    blind=$((blind + 1)); continue
  fi

  # https://github.com/OWNER/REPO.git -> OWNER/REPO
  slug="${url#https://github.com/}"; slug="${slug%.git}"
  if [[ "$slug" == "$url" || "$slug" != */* ]]; then
    echo "  ?  $name — source $url is not a github.com repo; cannot look"
    blind=$((blind + 1)); continue
  fi

  if ! body="$(fetch_plugin_json "$slug")" || [[ -z "$body" ]]; then
    echo "  ?  $name — could not read $slug/.claude-plugin/plugin.json"
    echo "     (gh missing, unauthenticated, or no access to a private repo)"
    blind=$((blind + 1)); continue
  fi

  actual="$(jq -r '.version // empty' <<<"$body" 2>/dev/null)"
  if [[ -z "$actual" ]]; then
    echo "  ?  $name — $slug has a plugin.json with no .version; cannot compare"
    blind=$((blind + 1)); continue
  fi

  if [[ "$actual" == "$declared" ]]; then
    echo "  ok $name — catalogue $declared matches $slug"
    matched=$((matched + 1))
  else
    echo "::error::$name: catalogue declares $declared but $slug publishes $actual"
    mismatched=$((mismatched + 1))
  fi
done < <(jq -r '
  .plugins[]
  | [ .name,
      .version,
      (if (.source | type) == "object" then (.source.url // "") else "" end)
    ] | @tsv' "$MANIFEST")

echo
echo "$matched matched, $mismatched mismatched, $blind not looked up"

if (( mismatched > 0 )); then
  exit 1
fi
if (( blind > 0 )); then
  echo "Some plugins were not looked up. That is not a pass — see the ? lines above."
  exit 2
fi
exit 0
