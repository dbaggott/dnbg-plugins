# Setup: tools, `gh` login, Claude Code version

Part of the `setup` skill. Read this when `tools`, `gh-auth` or `claude-code` is
in the check's `open`, and act on those of the three that are.

## `tools`

`missing=` on the `check=tools` line lists what is not on `PATH`. Say what each
missing one disables, and leave installing it to the user:

| Tool | Without it |
| --- | --- |
| `jq` | Enforcement is off: neither blocking hook can read its input. Subagents do not receive the always-on rules, and no role's state can be read |
| `git` | The worktree hook never fires |
| `gh` | No workflow skill can run: every PR, issue and review operation goes through it |
| `python3` | A role's GitHub App cannot be created |
| `openssl` | No role token can be minted, so a role with an App cannot post |
| `curl` | No role token can be minted, so a role with an App cannot post |

The hooks fail open, so a missing `jq` or `git` stops protecting the user's
work without stopping it. With `jq` missing, `check=roles` reads `unknown`:
once it is installed, run the skill's check again before saying anything about
roles.

## `gh-auth`

`state=none` means `gh` has no stored login, so no skill can reach GitHub and a
role that falls back to the user's account has no account to post as. The login
is interactive: ask the user to type `! gh auth login`.

## `claude-code`

`state=below` means the client's `version=` is older than `floor=`, the oldest
version the plugin is known to work on. Nothing stops an older client loading
it, and what breaks is not announced. Ask the user to update Claude Code.
