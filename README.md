# crbiz-claude-plugins

CRBiz's internal Claude Code plugin marketplace.

This repository is **public** and holds only the catalogue
(`.claude-plugin/marketplace.json`). The plugins it lists live in **private**
repositories, so the catalogue being visible does not make the plugins
installable — see [Access](#access).

## Plugins

| Plugin | Description | Source |
| --- | --- | --- |
| `crbiz-pm` | PM-as-Configuration-Overlay grammar: bidirectional HTML board, chip-spawn wrapper, Tie-back protocol, lean PM context. | [`crbiz-sysadmin/crbiz-pm`](https://github.com/crbiz-sysadmin/crbiz-pm) (private) |
| `crbiz-skills` | Zoho consulting skills: platform mechanics, Deluge, the product catalogue and licensing architecture, under six product specialists — CRM, Desk, Analytics, Catalyst, FSM and the finance suite. Plus BRD/PRD elicitation and WordPress/SEO migration. | [`crbiz-sysadmin/crbiz-skills`](https://github.com/crbiz-sysadmin/crbiz-skills) (private) |

### Retired

`pm-board-keeper` was delisted in catalogue v0.3.0. `crbiz-pm` v2.0 lifted the
board skill, the keeper agent and the six `pm-board-*` commands, so the plugin
had nothing left that `crbiz-pm` does not carry.

It is delisted, not deleted. The source still lives at
[`crbiz-sysadmin/pm-board`](https://github.com/crbiz-sysadmin/pm-board) —
removing a catalogue entry never touches the repository it points at.

### Retiring a plugin: three options, not two

Delisting has three outcomes for anyone who still has the plugin enabled, and
the difference is entirely in the `renames` map:

| What you do | What the user gets |
| --- | --- |
| Remove the entry, **no** `renames` mapping | A hard `plugin-not-found` error. The plugin does not load and nothing explains why. Avoid. |
| Remove the entry, map the old name to **`null`** | Claude Code drops the key and reports that the plugin was removed from the marketplace. Clean, honest, no successor. |
| Remove the entry, map the old name to **another plugin** | Claude Code rewrites the key to that plugin across user, project and local settings and shows a one-line notice. |

`pm-board-keeper` uses the third, pointing at `crbiz-pm`, because `crbiz-pm`
genuinely carries what it did and landing someone on the successor beats
landing them nowhere.

**Two honest caveats.** The migration is not seamless: because the source is
remote, Claude Code reports `plugin-cache-miss` after the rewrite and the user
must run `/plugin install crbiz-pm@crbiz-claude-plugins` once. And `crbiz-pm`
is substantially larger than what it replaces, so the rewrite enrols them in a
bigger context cost than the plugin they originally chose. Mapping to `null`
would have avoided both at the price of leaving them with nothing. Given a
manual step is unavoidable either way, that trade was close — if the blast
radius were wider than a couple of installs, `null` would be the safer default.

**Never delete a `renames` entry**, even long after everyone has migrated —
that is what turns a graceful outcome back into `plugin-not-found`. The map is
append-only. To retire something else later, add an entry rather than editing an
existing one; Claude Code follows chains, so `a → b` plus `b → c` resolves `a`
all the way to `c`.

## Install

```
/plugin marketplace add crbiz-sysadmin/crbiz-claude-plugins
/plugin install crbiz-pm@crbiz-claude-plugins
/plugin install crbiz-skills@crbiz-claude-plugins
```

Plugin skills are namespaced by plugin name, so `crbiz-pm` provides
`/crbiz-pm:pm-board`, `/crbiz-pm:pm-init` and so on.

`crbiz-skills` is almost entirely model-invoked rather than slash-invoked — its
skills fire on description match when a Zoho question comes up, so there is
usually nothing to type. The exception is the SessionStart hook, which applies
the house working conventions from the first reply.

## Access

Adding the marketplace and installing a plugin are **two separate fetches**.
The first reads this public repository. The second clones a private one. A
machine can complete the first and fail the second, which reads as the
marketplace working but the plugin being missing.

Check before you need it:

```bash
./scripts/check-plugin-access.sh
```

It runs `git ls-remote` against every git-backed source in the catalogue and
reports which ones this machine can actually reach, with the remedy for any it
cannot. Exit code is non-zero if anything is unreachable, so it also works as a
CI or onboarding gate.

### Authorising git

Claude Code uses your existing git credentials for `/plugin` operations — it has
no credential store of its own. Any one of these is enough for interactive use:

- `gh auth login` followed by `gh auth setup-git`
- an SSH key loaded in `ssh-agent`, with the host in `known_hosts`
- a configured `credential.helper` (macOS Keychain, `git-credential-store`)

Access is per-account and per-machine. A working checkout on your laptop tells
you nothing about whether a cloud session or a colleague's machine can fetch the
same repository.

### Background updates

This is the case worth knowing about, because it is the one that fails quietly.

**Auto-update is off by default** for third-party marketplaces such as this one,
so by default nothing runs in the background and there is nothing to fail. If
you turn it on (`/plugin` → **Marketplaces** → *Enable auto-update*), one thing
changes that is easy to miss:

> Background refresh disables git credential helpers.

So a private HTTPS remote that installs perfectly by hand can fail on every
background refresh, because the helper that was supplying the credential is not
consulted. The plugin keeps working — you just stop receiving updates, and the
only signal is the `/plugin` **Errors** tab, which nobody opens unprompted.

Three ways to avoid it, in order of preference:

1. **Use SSH**, which authenticates from `ssh-agent` and is unaffected:

   ```bash
   git config --global url."git@github.com:".insteadOf "https://github.com/"
   ssh-add ~/.ssh/id_ed25519
   ```

2. **Keep the existing clone when a refresh fails**, so a failed background pull
   degrades to "not updated" rather than losing the marketplace:

   ```bash
   export CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE=1
   ```

3. **Leave auto-update off** and refresh deliberately. `/plugin install` with an
   explicit `name@marketplace` refreshes the catalogue first even when
   auto-update is disabled, and reports `marketplace not refreshed` if that fetch
   failed — which is a louder signal than the background path gives you.

   ```
   /plugin marketplace update crbiz-claude-plugins
   ```

A token-embedding git URL rewrite also works and is documented upstream. It is
listed last deliberately: it writes a credential into `~/.gitconfig` in
cleartext. If you use it, use a read-only token.

## How updates work

Plugin code lives in the linked source repos; this repository holds only the
catalogue. To ship a change:

1. Edit the plugin's own repository.
2. Bump `version` in its `.claude-plugin/plugin.json`.
3. Bump the matching `version` in this repository's `marketplace.json` entry,
   and `metadata.version` at the top level.

The second half of step 3 is now enforced: CI fails a pull request that changes
a plugin entry without moving `metadata.version` (gate **M11** under
[Validation](#validation)).

Step 3 is not cosmetic. For git-backed sources, a declared `version` **pins**
the plugin: users keep the cached copy until that string changes, no matter how
many commits you push. Forgetting it is indistinguishable from the update not
working.

## Adding a plugin to the catalogue

Add an entry to `.claude-plugin/marketplace.json`, then verify:

```bash
./scripts/check-plugin-access.sh <plugin-name>
claude plugin validate .
```

Private plugin sources must share this marketplace's GitHub owner
(`crbiz-sysadmin`) if the marketplace is ever distributed through claude.ai
organisation settings. Relative-path sources (`./plugins/<name>`) would publish
the plugin's code into this public repository, so they are not an option for
anything private.

## Validation

`.claude-plugin/marketplace.json` is what every `claude plugin` install in the
estate resolves. A malformed file breaks every install, for everyone, at once.
Until CI landed, nothing in this repository read the file — the last change to
it was hand-parsed by a human before merging, which worked and does not scale.

Every pull request and every push to `main` now runs
[`.github/workflows/ci.yml`](.github/workflows/ci.yml):

| Gate | What it catches |
| --- | --- |
| **M1** | the manifest does not parse as JSON |
| **M2-M3** | a missing or mistyped top-level key; `metadata.version` that is not SemVer |
| **M4-M7** | an entry missing `name`, `version`, `source`, `description`, `author` or `homepage`; a non-SemVer version; a name that is not a lowercase-hyphen slug; a duplicate name; a source that is not an https `.git` URL |
| **M8** | a description that contradicts the version it ships under — the drift that had the catalogue declaring `2.3.0` while its description read "v2.2.0 of the PM-on-CC discipline" |
| **M9** | a rename pointing at a plugin this catalogue does not list, or shadowing one it does |
| **M10** | a **deleted** rename entry. The map is append-only for the reason given above: deleting an entry turns a graceful migration back into a hard `plugin-not-found` |
| **M11** | a changed plugin entry without a `metadata.version` bump |
| **M12** | a listed plugin that this README never mentions |

Run them yourself:

```bash
python3 .github/scripts/check-marketplace.py     # the gates above
./tests/check-marketplace.sh                     # prove they still fail when they should
```

The checker exits `0` when every check passed, `1` when one failed, and `2` when
it could not read the manifest at all. Checks that need a base revision to
compare against are reported as `SKIPPED` when there isn't one — never as passes.

### The cross-repo check is blind in CI

[`.github/scripts/check-source-versions.sh`](.github/scripts/check-source-versions.sh)
asks a different question: does each entry's declared `version` match what its
source repository actually publishes in `.claude-plugin/plugin.json`?

It is a separate script because it can fail for a reason that has nothing to do
with the manifest. **This repository is public and the plugins it lists are
private**, so a workflow's default `GITHUB_TOKEN` cannot read them. In CI the
script therefore exits `2` — *could not look* — and the job records a warning.
That is deliberate: a blind check must not report a pass, and must not fail the
build for a credentials problem either.

It is a real check when run by someone who has credentials:

```bash
gh auth login && ./.github/scripts/check-source-versions.sh
```

To make it real in CI, add a repository secret with read access to the plugin
repos named `PLUGIN_READ_TOKEN`; the workflow already prefers it over the
default token. Its matching and mismatching branches are exercised against a
stubbed `gh` by [`tests/check-source-versions.sh`](tests/check-source-versions.sh),
so they are tested even while they cannot run for real here.
