#!/usr/bin/env bash
# check-plugin-access.sh — verify this machine can actually fetch every plugin
# listed in the marketplace.
#
# Why this exists: the catalogue in this repo is public, but the plugins it
# points at live in private repositories. A machine without working git
# credentials can add the marketplace successfully and then fail to install or
# update anything, because the catalogue and the plugin code are fetched
# separately. Background refresh is the worst case — it runs without credential
# helpers, so a private HTTPS remote can fail there while working fine when you
# install by hand.
#
# Run this before you need it, rather than diagnosing it at the point of use.
#
#   ./scripts/check-plugin-access.sh          # check every plugin
#   ./scripts/check-plugin-access.sh crbiz-pm # check one
#
# Exit 0 if every source is reachable, 1 otherwise.

set -uo pipefail

MANIFEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude-plugin/marketplace.json"
ONLY="${1:-}"

command -v jq >/dev/null || { echo "jq is required but not installed." >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }

# Fail fast instead of blocking on an interactive credential prompt. Without
# these, an unauthenticated HTTPS fetch hangs waiting for a username that no
# one is going to type — which is the shape the original problem takes.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"

pass=0 fail=0 skip=0

# Resolve a marketplace plugin entry to something git can talk to.
# Returns empty for source types that aren't git-backed.
source_url() {
  local entry="$1" kind
  kind=$(jq -r 'if (.source|type) == "string" then "path" else .source.source end' <<<"$entry")
  case "$kind" in
    github)     jq -r '"https://github.com/" + .source.repo + ".git"' <<<"$entry" ;;
    url)        jq -r '.source.url' <<<"$entry" ;;
    git-subdir) jq -r '.source.url' <<<"$entry" ;;
    *)          echo "" ;;
  esac
}

printf '%s\n' "Checking plugin sources in $(basename "$MANIFEST")"
printf '%s\n\n' "$(printf '%.0s-' {1..60})"

while IFS= read -r entry; do
  name=$(jq -r '.name' <<<"$entry")
  [[ -n "$ONLY" && "$ONLY" != "$name" ]] && continue

  url=$(source_url "$entry")
  if [[ -z "$url" ]]; then
    kind=$(jq -r 'if (.source|type) == "string" then "relative path" else .source.source end' <<<"$entry")
    printf '  %-22s SKIP  (%s source — nothing to fetch)\n' "$name" "$kind"
    skip=$((skip+1))
    continue
  fi

  if err=$(git ls-remote --heads "$url" 2>&1 >/dev/null); then
    printf '  %-22s OK    %s\n' "$name" "$url"
    pass=$((pass+1))
  else
    printf '  %-22s FAIL  %s\n' "$name" "$url"
    printf '  %-22s       %s\n' "" "$(head -n1 <<<"$err")"
    fail=$((fail+1))
  fi
done < <(jq -c '.plugins[]' "$MANIFEST")

printf '\n%s\n' "$(printf '%.0s-' {1..60})"
printf '%d reachable, %d unreachable, %d skipped\n' "$pass" "$fail" "$skip"

if (( fail == 0 )); then
  # Reachable by hand is not the same as reachable in the background. Say so,
  # because this is exactly the case that looks fine until it silently isn't.
  if git config --get-regexp '^credential\.' >/dev/null 2>&1; then
    # A helper can be global (credential.helper) or scoped to one host
    # (credential.https://github.com.helper). Only the first is readable by
    # name, so fall back rather than printing an empty value.
    helper=$(git config --get credential.helper 2>/dev/null)
    printf '\nCredential helper: %s\n' "${helper:-configured (host-scoped)}"
    printf 'Interactive installs will work. Background refresh runs WITHOUT\n'
    printf 'credential helpers, so an HTTPS remote can still fail there. See\n'
    printf 'the "Background updates" section of README.md.\n'
  elif ssh-add -l >/dev/null 2>&1; then
    printf '\nSSH agent has keys loaded. Background refresh over SSH will work.\n'
  else
    printf '\nNo credential helper and no keys in ssh-agent were detected, yet\n'
    printf 'the fetches succeeded — you may be relying on a cached credential\n'
    printf 'that will expire. See README.md.\n'
  fi
  exit 0
fi

cat <<'REMEDY'

To fix, pick one:

  1. Authorise git for GitHub (simplest if you use the gh CLI):
       gh auth login && gh auth setup-git

  2. Use SSH, which also survives background refresh:
       git config --global url."git@github.com:".insteadOf "https://github.com/"
     with your key loaded:  ssh-add ~/.ssh/id_ed25519

  3. Confirm your account can actually read the repository. These are private;
     access is per-account, so a working checkout on another machine proves
     nothing about this one.

REMEDY
exit 1
