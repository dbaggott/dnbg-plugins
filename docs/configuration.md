# Configuration

Settings are stored in `~/.claude/settings.json`, under
`pluginConfigs.<plugin>@dnbg.options`. Edit them there or with the command
given for each plugin.

They apply to every repo. A repo's own `.claude/settings.json` is not read.

## Settings

An invalid value falls back to its default. A path may use only letters, digits
and `. _ - /`.

### `dnbg-workflow`

Edit with `/plugin configure dnbg-workflow`.

| Setting | Default | Controls |
| --- | --- | --- |
| `owners` | empty | GitHub orgs and logins, comma-separated, whose repos the hooks enforce on. Empty: nothing is ever blocked. `/dnbg-workflow:setup` asks for it |
| `worktree_path` | `.worktrees` | Directory worktrees are created in, relative to the repo |
| `claim_label` | `assigned:agent-session` | Label that marks an issue as claimed. Must start with `assigned:` |
| `findings_dir` | `~/.claude/dnbg-findings` | Where agents write what their reports found about the code. Absolute or under `~/` |
| `retrospectives` | off | On: each agent writes a file on where the process slowed it when its work ends. Off: it reports only where a skill was wrong, in chat |
| `retrospective_dir` | `~/.claude/dnbg-retrospectives` | Where those files go. Absolute or under `~/` |
| `version_stamp` | off | On: PR descriptions, reviews and issue claim comments end with a hidden `<!-- dnbg-workflow <version> -->` |

### `dnbg-agent-summaries`

Edit with `/plugin configure dnbg-agent-summaries`.

| Setting | Default | Controls |
| --- | --- | --- |
| `summary_dir` | `~/.claude/dnbg-agent-summaries` | Where agents write summary files. Absolute or under `~/` |

### `dnbg-work-summary`

Edit with `/plugin configure dnbg-work-summary`.

| Setting | Default | Controls |
| --- | --- | --- |
| `owners` | empty | GitHub orgs and logins, comma-separated, whose repos a recap searches. Empty: it asks each time. Separate from `dnbg-workflow`'s `owners` |

## `velocity-tradeoff`

Off by default. Enable it per repo by adding a section like this to the repo's
`CLAUDE.md`:

```markdown
## How to size a change here

Load `dnbg-workflow:velocity-tradeoff` when sizing a change or deciding
whether to split a PR. This repo has opted in, and only the operator ends
that.
```

## The setup notice

Each session opens with a one-line notice while `owners` is empty or the
reviewer has no bot. Answering none or declining the bot in
`/dnbg-workflow:setup` turns it off. Deleting
`~/.config/dnbg/setup-acknowledged` brings it back.

## Agent roles

Each role posts under its own GitHub App once `/dnbg-workflow:reviewer-setup`
has created one.

| Role | Posts | Without an App |
| --- | --- | --- |
| `reviewer` | PR reviews and issue verdicts | Refuses to run |
| `author` | PRs, issues, comments and pushes | Posts as you |
| `orchestrator` | Claims, questions and tracking-issue edits | Posts as you |

[`SECURITY.md`](../SECURITY.md) lists each App's permissions and what a leaked
key can reach.

Each role reads `~/.config/dnbg/<role>/` (under `$XDG_CONFIG_HOME` when that is
set). Environment variables override it, with `<ROLE>` as `REVIEWER`, `AUTHOR`
or `ORCHESTRATOR`:

| Variable | Overrides |
| --- | --- |
| `DNBG_<ROLE>_CONFIG_DIR` | The directory itself |
| `DNBG_<ROLE>_APP_ID`, `_INSTALLATION_ID`, `_SLUG` | The same fields in its `config.json` |
| `DNBG_<ROLE>_PRIVATE_KEY`, `_PRIVATE_KEY_COMMAND` | Where the key comes from, below |

## Role Apps' private keys

The first source that yields a key is used:

| Order | Source | Notes |
| --- | --- | --- |
| 1 | `DNBG_<ROLE>_PRIVATE_KEY` | The PEM itself. For CI: with `DNBG_<ROLE>_APP_ID` set, no file is needed |
| 2 | `DNBG_<ROLE>_PRIVATE_KEY_COMMAND`, or `private_key_command` in `config.json` | A command that prints the PEM, such as `op read` or `pass show`. Runs on every write, so one that prompts will prompt often |
| 3 | `~/.config/dnbg/<role>/private-key.pem` | The default: plaintext, mode `0600` |

A key from 1 or 2 is never written to disk. A config directory or key file that
is group- or world-writable is refused.
