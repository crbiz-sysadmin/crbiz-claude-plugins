#!/usr/bin/env python3
"""check-marketplace.py — validate .claude-plugin/marketplace.json.

Why this exists: this catalogue is what every `claude plugin` install in the
estate resolves. A malformed file breaks every install, for everyone, at once.
Until this script landed, nothing in this repository read the file at all — the
last change to it was hand-parsed by a human before merging, which worked and
does not scale.

Every check here is local: it reads the manifest, the README and (optionally) the
manifest as it stands on the base branch. Nothing here talks to the network, so
nothing here can verify a claim about a *source* repository — that is
check-source-versions.sh, which is a separate script precisely because it can
fail for a reason (no credentials) that has nothing to do with the manifest.

Exit codes, deliberately three:
  0  every check ran and passed
  1  at least one check ran and failed
  2  could not look — the manifest is missing or unreadable

2 is not 0. "I looked and found nothing wrong" and "I could not look" are
different answers and a gate that conflates them reports success when it is
blind.

Usage:
  check-marketplace.py [--manifest PATH] [--readme PATH] [--base-manifest PATH]

--base-manifest is the same file as it stands on the merge base. The two checks
that need it (renames are append-only; the catalogue version moves when an entry
does) are reported as SKIPPED when it is absent, never as passed.
"""

import argparse
import json
import re
import sys

SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")
SLUG = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
# Matches the "vX.Y.Z of the ... discipline" claim some descriptions carry.
# The check is a contradiction check, not a style rule: the phrase is optional,
# but where it appears it may not disagree with the declared version.
DISCIPLINE_VERSION = re.compile(r"\bv(\d+\.\d+(?:\.\d+)?)\s+of the\s+([A-Za-z0-9 _-]*?)\s*discipline\b")

failures = []
skipped = []
passed = []


def fail(check, msg):
    failures.append(f"{check}: {msg}")


def ok(check, msg):
    passed.append(f"{check}: {msg}")


def skip(check, msg):
    skipped.append(f"{check}: {msg}")


def load(path, what):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:
        print(f"::error::Could not read {what} at {path}: {exc}", file=sys.stderr)
        return None


def check_structure(m):
    """M1-M3: the top-level shape the plugin client relies on."""
    for key, typ, label in (
        ("name", str, "string"),
        ("owner", dict, "object"),
        ("metadata", dict, "object"),
        ("plugins", list, "array"),
    ):
        if key not in m:
            fail("M2", f"top-level key '{key}' is missing")
        elif not isinstance(m[key], typ):
            fail("M2", f"top-level '{key}' must be a {label}, got {type(m[key]).__name__}")

    if isinstance(m.get("name"), str) and not m["name"].strip():
        fail("M2", "top-level 'name' is empty")

    owner = m.get("owner")
    if isinstance(owner, dict):
        for key in ("name", "url"):
            if not isinstance(owner.get(key), str) or not owner[key].strip():
                fail("M2", f"owner.{key} must be a non-empty string")

    meta = m.get("metadata")
    if isinstance(meta, dict):
        if not isinstance(meta.get("description"), str) or not meta["description"].strip():
            fail("M2", "metadata.description must be a non-empty string")
        version = meta.get("version")
        if not isinstance(version, str) or not SEMVER.match(version):
            fail("M3", f"metadata.version {version!r} is not SemVer")
        else:
            ok("M3", f"catalogue version {version} is SemVer")

    plugins = m.get("plugins")
    if isinstance(plugins, list) and not plugins:
        fail("M2", "'plugins' is an empty array — a catalogue that lists nothing")
    if not failures:
        ok("M2", "top-level keys present and well-typed")


def check_plugins(m):
    """M4-M8: every entry carries what an install needs."""
    plugins = m.get("plugins")
    if not isinstance(plugins, list):
        return []

    names = []
    for i, p in enumerate(plugins):
        where = f"plugins[{i}]"
        if not isinstance(p, dict):
            fail("M4", f"{where} is not an object")
            continue

        name = p.get("name")
        if not isinstance(name, str) or not name.strip():
            fail("M4", f"{where}.name must be a non-empty string")
        else:
            where = f"plugins[{i}] ({name})"
            names.append(name)
            if not SLUG.match(name):
                fail("M6", f"{where}: name is not a lowercase-hyphen slug")

        for key in ("version", "description", "homepage"):
            if not isinstance(p.get(key), str) or not p[key].strip():
                fail("M4", f"{where}.{key} must be a non-empty string")

        version = p.get("version")
        if isinstance(version, str) and not SEMVER.match(version):
            fail("M5", f"{where}: version {version!r} is not SemVer")

        author = p.get("author")
        if not isinstance(author, dict):
            fail("M4", f"{where}.author must be an object")
        elif not isinstance(author.get("name"), str) or not author["name"].strip():
            fail("M4", f"{where}.author.name must be a non-empty string")

        src = p.get("source")
        if isinstance(src, str):
            if not src.strip():
                fail("M7", f"{where}: string source is empty")
        elif isinstance(src, dict):
            if src.get("source") != "url":
                fail("M7", f"{where}: source.source must be \"url\", got {src.get('source')!r}")
            url = src.get("url")
            if not isinstance(url, str) or not url.startswith("https://"):
                fail("M7", f"{where}: source.url must be an https URL, got {url!r}")
            elif not url.endswith(".git"):
                fail("M7", f"{where}: source.url {url!r} does not end in .git")
        else:
            fail("M7", f"{where}.source must be an object or a string")

        for key in ("category",):
            if key in p and (not isinstance(p[key], str) or not p[key].strip()):
                fail("M4", f"{where}.{key}, when present, must be a non-empty string")
        if "tags" in p:
            tags = p["tags"]
            if not isinstance(tags, list) or not all(isinstance(t, str) and t.strip() for t in tags):
                fail("M4", f"{where}.tags, when present, must be an array of non-empty strings")

    dupes = sorted({n for n in names if names.count(n) > 1})
    if dupes:
        fail("M6", f"duplicate plugin names: {', '.join(dupes)}")

    if not any(f.startswith(("M4", "M5", "M6", "M7")) for f in failures):
        ok("M4-M7", f"{len(plugins)} plugin entries carry name, version, source, description, author, homepage")
    return names


def check_description_version(m):
    """M8: a description may not contradict the version it ships under."""
    checked = 0
    for p in m.get("plugins", []):
        if not isinstance(p, dict):
            continue
        name, desc, version = p.get("name"), p.get("description"), p.get("version")
        if not isinstance(desc, str) or not isinstance(version, str):
            continue
        for claimed, subject in DISCIPLINE_VERSION.findall(desc):
            checked += 1
            # "v2.3" and "v2.3.0" both name the 2.3.0 line; compare on the
            # components the description actually states.
            parts = claimed.split(".")
            if version.split(".")[: len(parts)] != parts:
                fail(
                    "M8",
                    f"{name}: description claims \"v{claimed} of the {subject} discipline\" "
                    f"but the entry declares version {version}",
                )
    if checked and not any(f.startswith("M8") for f in failures):
        ok("M8", f"{checked} in-description version claim(s) agree with the declared version")
    elif not checked:
        skip("M8", "no description states a \"vX.Y of the ... discipline\" version")


def check_renames(m, names):
    """M9: the rename map is what stands between a delisting and plugin-not-found."""
    renames = m.get("renames")
    if renames is None:
        skip("M9", "no renames map present")
        return
    if not isinstance(renames, dict):
        fail("M9", "'renames' must be an object")
        return
    for old, new in renames.items():
        if not isinstance(old, str) or not old.strip():
            fail("M9", f"rename key {old!r} must be a non-empty string")
            continue
        if old in names:
            fail("M9", f"rename key '{old}' collides with a listed plugin of the same name")
        if new is None:
            continue
        if not isinstance(new, str) or not new.strip():
            fail("M9", f"rename '{old}' must map to a plugin name or null, got {new!r}")
        elif new not in names and new not in renames:
            fail("M9", f"rename '{old}' -> '{new}' names a plugin this catalogue does not list")
    if not any(f.startswith("M9") for f in failures):
        ok("M9", f"{len(renames)} rename(s) resolve to a listed plugin or null")


def check_against_base(m, base):
    """M10-M11: the two disciplines the README states and nothing enforced."""
    # M10 — the README says "Never delete a renames entry", because deleting one
    # turns a graceful migration back into a hard plugin-not-found for anyone
    # who has not upgraded. The map is append-only.
    base_renames = base.get("renames") or {}
    cur_renames = m.get("renames") or {}
    if not isinstance(base_renames, dict) or not isinstance(cur_renames, dict):
        fail("M10", "cannot compare rename maps: one side is not an object")
    else:
        for old, new in base_renames.items():
            if old not in cur_renames:
                fail("M10", f"rename '{old}' was deleted — the map is append-only")
            elif cur_renames[old] != new:
                fail("M10", f"rename '{old}' changed from {new!r} to {cur_renames[old]!r}")
        if not any(f.startswith("M10") for f in failures):
            ok("M10", f"{len(base_renames)} base rename(s) preserved")

    # M11 — an entry that changes without the catalogue version moving ships a
    # different catalogue under a version someone has already resolved.
    def entries(man):
        return {
            p.get("name"): p
            for p in man.get("plugins", [])
            if isinstance(p, dict) and isinstance(p.get("name"), str)
        }

    cur, old = entries(m), entries(base)
    changed = sorted(
        {n for n in set(cur) | set(old) if cur.get(n) != old.get(n)}
    )
    cur_v = (m.get("metadata") or {}).get("version")
    old_v = (base.get("metadata") or {}).get("version")
    if changed and cur_v == old_v:
        fail(
            "M11",
            f"plugin entries changed ({', '.join(changed)}) but metadata.version "
            f"is still {cur_v} — bump the catalogue version",
        )
    elif changed:
        ok("M11", f"entries changed ({', '.join(changed)}); catalogue {old_v} -> {cur_v}")
    else:
        ok("M11", "no plugin entry changed against the base")


def check_readme(m, readme):
    """M12: a catalogue entry nobody documented is one nobody can choose."""
    missing = [
        p["name"]
        for p in m.get("plugins", [])
        if isinstance(p, dict) and isinstance(p.get("name"), str)
        and f"`{p['name']}`" not in readme
    ]
    if missing:
        fail("M12", f"README.md does not mention: {', '.join(missing)}")
    else:
        ok("M12", "every listed plugin appears in README.md")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default=".claude-plugin/marketplace.json")
    ap.add_argument("--readme", default="README.md")
    ap.add_argument("--base-manifest")
    args = ap.parse_args()

    raw = load(args.manifest, "marketplace manifest")
    if raw is None:
        return 2

    try:
        m = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"::error::M1: {args.manifest} is not valid JSON: {exc}", file=sys.stderr)
        print("M1: FAIL — manifest does not parse", file=sys.stderr)
        return 1
    ok("M1", "manifest parses as JSON")

    if not isinstance(m, dict):
        print(f"::error::M1: {args.manifest} must be a JSON object", file=sys.stderr)
        return 1

    check_structure(m)
    names = check_plugins(m)
    check_description_version(m)
    check_renames(m, names)

    if args.base_manifest:
        base_raw = load(args.base_manifest, "base manifest")
        if base_raw is None:
            skip("M10-M11", "base manifest unreadable")
        else:
            try:
                base = json.loads(base_raw)
            except json.JSONDecodeError as exc:
                skip("M10-M11", f"base manifest does not parse ({exc}) — nothing to compare against")
            else:
                check_against_base(m, base if isinstance(base, dict) else {})
    else:
        skip("M10-M11", "no --base-manifest given (append-only renames, catalogue bump)")

    readme = load(args.readme, "README")
    if readme is None:
        skip("M12", "README unreadable")
    else:
        check_readme(m, readme)

    for line in passed:
        print(f"  ok      {line}")
    for line in skipped:
        print(f"  SKIPPED {line}")
    for line in failures:
        print(f"::error::{line}")

    print()
    print(f"{len(passed)} passed, {len(skipped)} skipped, {len(failures)} failed")
    if skipped:
        print("Skipped checks did not run. They are not passes.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
