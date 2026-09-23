#!/usr/bin/env bash
# check-marketplace.sh — mutation tests for .github/scripts/check-marketplace.py
#
# A guard that has never been seen to fail is not known to work. Each case below
# takes the REAL manifest, breaks exactly one thing, and asserts the checker says
# so. The fixture is part of the assertion: mutating the live file (rather than a
# hand-built minimal one) is what stops a check from passing because the fixture
# never reached the branch it guards.
#
# Assertions are on the MESSAGE, not the exit code. A checker that exits 1 for the
# wrong reason is not passing the test it appears to pass.
#
#   ./tests/check-marketplace.sh
#
# Exit 0 if every case behaves, 1 otherwise.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT/.github/scripts/check-marketplace.py"
MANIFEST="$ROOT/.claude-plugin/marketplace.json"
README="$ROOT/README.md"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0

# mutate <python-expression-file> -> writes $WORK/mutated.json
# The script body receives `m` (the parsed manifest) and mutates it in place.
mutate() {
  python3 - "$MANIFEST" "$WORK/mutated.json" <<PY
import json, sys, collections
src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as fh:
    m = json.load(fh, object_pairs_hook=collections.OrderedDict)
$1
with open(dst, "w", encoding="utf-8") as fh:
    json.dump(m, fh, indent=2, ensure_ascii=False)
PY
}

# expect <name> <expected-exit> <expected-substring> -- <checker args...>
expect() {
  local name="$1" want_rc="$2" want_msg="$3"; shift 3
  [ "${1:-}" = "--" ] && shift
  local out rc
  out="$("$CHECKER" "$@" 2>&1)"; rc=$?

  if [ "$rc" != "$want_rc" ]; then
    printf '  FAIL %s\n       expected exit %s, got %s\n' "$name" "$want_rc" "$rc"
    printf '       output: %s\n' "$out" | head -5
    fail=$((fail + 1)); return
  fi
  if ! printf '%s' "$out" | grep -qF -- "$want_msg"; then
    printf '  FAIL %s\n       exit %s was right but the message was not.\n' "$name" "$rc"
    printf '       wanted substring: %s\n' "$want_msg"
    printf '       got: %s\n' "$out" | head -8
    fail=$((fail + 1)); return
  fi
  printf '  ok   %s\n' "$name"
  pass=$((pass + 1))
}

echo "== baseline =="
expect "pristine manifest passes" 0 "0 failed" -- --manifest "$MANIFEST" --readme "$README"

echo
echo "== could not look (exit 2 is not exit 0) =="
expect "missing manifest reports 2, not 0" 2 "Could not read" -- \
  --manifest "$WORK/does-not-exist.json" --readme "$README"

echo
echo "== M1 valid JSON =="
{ cat "$MANIFEST"; echo "trailing garbage"; } > "$WORK/mutated.json"
expect "M1 truncated/garbage JSON" 1 "is not valid JSON" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

python3 -c "
import sys
src, dst = sys.argv[1], sys.argv[2]
open(dst,'w').write(open(src).read()[:-40])
" "$MANIFEST" "$WORK/mutated.json"
expect "M1 truncated file" 1 "is not valid JSON" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

echo
echo "== M2 top-level shape =="
mutate 'del m["plugins"]'
expect "M2 plugins missing" 1 "top-level key 'plugins' is missing" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'm["owner"]["name"] = ""'
expect "M2 owner.name empty" 1 "owner.name must be a non-empty string" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'm["plugins"] = []'
expect "M2 empty catalogue" 1 "a catalogue that lists nothing" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'm["plugins"] = {"crbiz-pm": {}}'
expect "M2 plugins wrong type" 1 "must be a array" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

echo
echo "== M3 catalogue SemVer =="
mutate 'm["metadata"]["version"] = "0.4"'
expect "M3 two-component version" 1 "is not SemVer" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'm["metadata"]["version"] = "v0.4.2"'
expect "M3 leading v" 1 "is not SemVer" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

echo
echo "== M4 required plugin keys =="
mutate 'del m["plugins"][0]["homepage"]'
expect "M4 homepage missing" 1 ".homepage must be a non-empty string" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'del m["plugins"][1]["author"]'
expect "M4 author missing (second entry)" 1 ".author must be an object" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'm["plugins"][0]["tags"] = ["pm", 7]'
expect "M4 non-string tag" 1 "array of non-empty strings" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

echo
echo "== M5 plugin SemVer =="
mutate 'm["plugins"][0]["version"] = "2.3"'
expect "M5 two-component plugin version" 1 "is not SemVer" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

echo
echo "== M6 names =="
mutate 'm["plugins"][0]["name"] = "CRBiz_PM"'
expect "M6 non-slug name" 1 "not a lowercase-hyphen slug" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'm["plugins"][1]["name"] = m["plugins"][0]["name"]'
expect "M6 duplicate names" 1 "duplicate plugin names" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

echo
echo "== M7 source =="
mutate 'm["plugins"][0]["source"]["url"] = "http://github.com/crbiz-sysadmin/crbiz-pm.git"'
expect "M7 non-https source" 1 "must be an https URL" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'm["plugins"][0]["source"]["source"] = "github"'
expect "M7 unknown source type" 1 'source.source must be "url"' -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'm["plugins"][0]["source"] = 42'
expect "M7 source wrong type" 1 ".source must be an object or a string" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

echo
echo "== M8 description may not contradict the version =="
# THE MUTATIONS BELOW DERIVE FROM THE LIVE MANIFEST, NEVER A HARDCODED VERSION.
# They hardcoded "2.3.0" / "2.4.0" / "0.4.2" until 2026-09-23, and the release
# that moved the manifest to 2.4.0 walked straight into it: the M11 case that
# mutates the version TO "2.4.0" became a no-op against a manifest already
# saying 2.4.0, so it passed while testing nothing. A test that can be
# satisfied by not running is not a test, and this one had quietly become one.
CUR_VER=$(python3 -c 'import json;print(json.load(open("'"$MANIFEST"'"))["plugins"][0]["version"])')
CUR_CAT=$(python3 -c 'import json;print(json.load(open("'"$MANIFEST"'"))["metadata"]["version"])')

mutate 'import re; d = m["plugins"][0]["description"]; m["plugins"][0]["description"] = re.sub(r"v\d+\.\d+(\.\d+)? of the PM-on-CC discipline", "v0.1 of the PM-on-CC discipline", d)'
expect "M8 the live drift, re-applied" 1 "declares version $CUR_VER" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'm["plugins"][0]["version"] = "3.0.0"'
expect "M8 version bumped, description left behind" 1 'of the PM-on-CC discipline' -- \
  --manifest "$WORK/mutated.json" --readme "$README"

echo
echo "== M9 renames =="
mutate 'm["renames"]["pm-board-keeper"] = "no-such-plugin"'
expect "M9 rename to unlisted plugin" 1 "names a plugin this catalogue does not list" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'm["renames"]["crbiz-pm"] = "crbiz-skills"'
expect "M9 rename key collides with a live plugin" 1 "collides with a listed plugin" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

mutate 'm["renames"] = ["pm-board-keeper", "crbiz-pm"]'
expect "M9 renames wrong type" 1 "'renames' must be an object" -- \
  --manifest "$WORK/mutated.json" --readme "$README"

echo
echo "== M10/M11 need a base; absent, they are SKIPPED, not passed =="
expect "no base -> skipped, not passed" 0 "SKIPPED M10-M11" -- \
  --manifest "$MANIFEST" --readme "$README"

cp "$MANIFEST" "$WORK/base.json"

mutate 'del m["renames"]["pm-board-keeper"]'
expect "M10 deleted rename" 1 "the map is append-only" -- \
  --manifest "$WORK/mutated.json" --readme "$README" --base-manifest "$WORK/base.json"

mutate 'm["renames"]["pm-board-keeper"] = None'
expect "M10 rename repointed to null" 1 "changed from" -- \
  --manifest "$WORK/mutated.json" --readme "$README" --base-manifest "$WORK/base.json"

# 99.0.0 cannot collide with a real version, so this mutation stays a mutation.
# The description's claim moves with it, or M8 fires first and M11 is never
# reached — found by this harness when the original form bumped the version
# alone and went red on M8, which is the check doing its job.
mutate 'import re; m["plugins"][0]["version"] = "99.0.0"; m["plugins"][0]["description"] = re.sub(r"v\d+\.\d+(\.\d+)? of the PM-on-CC discipline", "v99.0 of the PM-on-CC discipline", m["plugins"][0]["description"])'
expect "M11 entry changed, catalogue not bumped" 1 "bump the catalogue version" -- \
  --manifest "$WORK/mutated.json" --readme "$README" --base-manifest "$WORK/base.json"

mutate 'import re; m["plugins"][0]["version"] = "99.0.0"; m["plugins"][0]["description"] = re.sub(r"v\d+\.\d+(\.\d+)? of the PM-on-CC discipline", "v99.0 of the PM-on-CC discipline", m["plugins"][0]["description"]); m["metadata"]["version"] = "99.0.0"'
expect "M11 entry changed and catalogue bumped" 0 "catalogue $CUR_CAT -> 99.0.0" -- \
  --manifest "$WORK/mutated.json" --readme "$README" --base-manifest "$WORK/base.json"

mutate 'pass'
expect "M11 nothing changed" 0 "no plugin entry changed" -- \
  --manifest "$WORK/mutated.json" --readme "$README" --base-manifest "$WORK/base.json"

echo '{ not json' > "$WORK/badbase.json"
expect "unparseable base is SKIPPED, not a pass" 0 "SKIPPED M10-M11" -- \
  --manifest "$MANIFEST" --readme "$README" --base-manifest "$WORK/badbase.json"

echo
echo "== M12 README =="
grep -v '`crbiz-skills`' "$README" > "$WORK/README.md"
expect "M12 plugin absent from README" 1 "README.md does not mention: crbiz-skills" -- \
  --manifest "$MANIFEST" --readme "$WORK/README.md"

echo
echo "-------------------------------------------"
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
