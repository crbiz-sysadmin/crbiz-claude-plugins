#!/usr/bin/env bash
# check-source-versions.sh (tests) — exercise every branch of the cross-repo check.
#
# Without this, the only path that ever runs is "could not look": the plugin
# repos are private and no CI token here can read them. A script whose matching
# and mismatching branches have never executed is not known to work, so each is
# driven here against a stubbed `gh`.
#
#   ./tests/check-source-versions.sh
#
# Exit 0 if every case behaves, 1 otherwise.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT/.github/scripts/check-source-versions.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

pass=0 fail=0

# Build a fake `gh` that answers the contents API with a chosen plugin.json per
# repo slug. Repos with no mapping 404 the way a private repo does to a token
# that cannot see it.
stub_gh() {
  cat > "$WORK/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
# Fake gh: args look like `gh api repos/OWNER/REPO/contents/... --jq .content`
path=""
for a in "$@"; do case "$a" in repos/*) path="$a";; esac; done
slug="${path#repos/}"; slug="${slug%%/contents/*}"
key="$(printf '%s' "$slug" | tr -c 'A-Za-z0-9' '_')"
file="$GH_STUB_DIR/$key.json"
if [ ! -f "$file" ]; then
  echo "gh: Not Found (HTTP 404)" >&2
  exit 1
fi
base64 -w0 < "$file" 2>/dev/null || base64 < "$file"
GHEOF
  chmod +x "$WORK/bin/gh"
}

set_repo() { # set_repo <owner/repo> <json-body>
  local key; key="$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"
  printf '%s' "$2" > "$WORK/stub/$key.json"
}

reset_stub() { rm -rf "$WORK/stub"; mkdir -p "$WORK/stub"; }

# expect <name> <want-rc> <want-substring> [PATH-override]
expect() {
  local name="$1" want_rc="$2" want_msg="$3" path_override="${4:-$WORK/bin:$PATH}"
  local out rc
  out="$(PATH="$path_override" GH_STUB_DIR="$WORK/stub" "$CHECKER" 2>&1)"; rc=$?
  if [ "$rc" != "$want_rc" ]; then
    printf '  FAIL %s\n       expected exit %s, got %s\n       output: %s\n' \
      "$name" "$want_rc" "$rc" "$out"
    fail=$((fail + 1)); return
  fi
  if ! printf '%s' "$out" | grep -qF -- "$want_msg"; then
    printf '  FAIL %s\n       exit %s right, message wrong.\n       wanted: %s\n       got: %s\n' \
      "$name" "$rc" "$want_msg" "$out"
    fail=$((fail + 1)); return
  fi
  printf '  ok   %s\n' "$name"
  pass=$((pass + 1))
}

stub_gh
DECLARED_PM="$(jq -r '.plugins[] | select(.name=="crbiz-pm") | .version' "$ROOT/.claude-plugin/marketplace.json")"
DECLARED_SK="$(jq -r '.plugins[] | select(.name=="crbiz-skills") | .version' "$ROOT/.claude-plugin/marketplace.json")"

echo "== every source agrees =="
reset_stub
set_repo crbiz-sysadmin/crbiz-pm     "{\"name\":\"crbiz-pm\",\"version\":\"$DECLARED_PM\"}"
set_repo crbiz-sysadmin/crbiz-skills "{\"name\":\"crbiz-skills\",\"version\":\"$DECLARED_SK\"}"
expect "both match -> 0" 0 "2 matched, 0 mismatched, 0 not looked up"

echo
echo "== a source has moved on and the catalogue has not =="
reset_stub
set_repo crbiz-sysadmin/crbiz-pm     '{"name":"crbiz-pm","version":"2.4.0"}'
set_repo crbiz-sysadmin/crbiz-skills "{\"name\":\"crbiz-skills\",\"version\":\"$DECLARED_SK\"}"
expect "mismatch -> 1, naming both versions" 1 "catalogue declares $DECLARED_PM but crbiz-sysadmin/crbiz-pm publishes 2.4.0"

echo
echo "== could not look is never a pass =="
reset_stub
expect "no repo readable -> 2" 2 "0 matched, 0 mismatched, 2 not looked up"

reset_stub
set_repo crbiz-sysadmin/crbiz-pm "{\"name\":\"crbiz-pm\",\"version\":\"$DECLARED_PM\"}"
expect "one readable, one not -> 2 (not 0)" 2 "1 matched, 0 mismatched, 1 not looked up"

reset_stub
set_repo crbiz-sysadmin/crbiz-pm     '{"name":"crbiz-pm"}'
set_repo crbiz-sysadmin/crbiz-skills "{\"name\":\"crbiz-skills\",\"version\":\"$DECLARED_SK\"}"
expect "plugin.json without .version -> 2" 2 "has a plugin.json with no .version"

echo
echo "== a real mismatch outranks a blind spot =="
reset_stub
set_repo crbiz-sysadmin/crbiz-pm '{"name":"crbiz-pm","version":"9.9.9"}'
expect "mismatch + unreadable -> 1" 1 "publishes 9.9.9"

echo
echo "== no gh at all =="
reset_stub
mkdir -p "$WORK/nogh"
for t in jq base64 tr grep printf cat mktemp; do
  src="$(command -v "$t" 2>/dev/null)" && ln -sf "$src" "$WORK/nogh/$t" 2>/dev/null
done
expect "gh missing -> 2, not 0" 2 "not looked up" "$WORK/nogh:/usr/bin:/bin"

echo
echo "-------------------------------------------"
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
