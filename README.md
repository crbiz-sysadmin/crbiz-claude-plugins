# crbiz-claude-plugins

CRBiz's internal Claude Code plugin marketplace.

## Plugins

| Plugin | Description | Source |
| --- | --- | --- |
| `pm-board-keeper` | Single-file HTML PM dashboard for chip-spawn workflows. | [`crbiz-sysadmin/pm-board`](https://github.com/crbiz-sysadmin/pm-board) (subdir `plugin/pm-board-keeper`) |

## Install

​```
/plugin marketplace add crbiz-sysadmin/crbiz-claude-plugins
/plugin install pm-board-keeper@crbiz-claude-plugins
​```

## How updates work

This repo holds only `.claude-plugin/marketplace.json`. Plugin code lives in the linked source repos. To update a plugin's code, edit the source repo and bump its `.claude-plugin/plugin.json` version — users get the update via `/plugin update`.
