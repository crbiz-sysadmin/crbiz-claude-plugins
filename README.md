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
| `pm-board-keeper` | **Deprecated** in favour of `crbiz-pm` v2.0, which lifts the board skill, the keeper agent and the six `pm-board-*` commands. | [`crbiz-sysadmin/pm-board`](https://github.com/crbiz-sysadmin/pm-board), subdir `plugin/pm-board-keeper` |

## Install

```
/plugin marketplace add crbiz-sysadmin/crbiz-claude-plugins
/plugin install crbiz-pm@crbiz-claude-plugins
```

Plugin skills are namespaced by plugin name, so `crbiz-pm` provides
`/crbiz-pm:pm-board`, `/crbiz-pm:pm-init` and so on.

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
