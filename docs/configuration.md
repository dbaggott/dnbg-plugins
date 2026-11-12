# Configuration

Settings are stored in `~/.claude/settings.json`, under
`pluginConfigs.<plugin>@dnbg.options`. Edit them there or with the command
given for each plugin.

They apply to every repo. A repo's own `.claude/settings.json` is not read.

A change reaches a session that is already running after `/reload-plugins`.

## Settings

An invalid value falls back to its default. A path may use only letters, digits
and `. _ - /`.

### `dnbg-workflow`

Edit with `/plugin configure dnbg-workflow`.

| Setting | Default | Controls |
| --- | --- | --- |
| `owners` | empty | GitHub orgs and logins, comma-separated, whose repos the hooks enforce on. Empty: nothing is ever blocked. `/dnbg-workflow:setup` asks for it |
| `worktree_path` | `.worktrees` | Directory worktrees are created in. Relative to the repo and inside it |
| `claim_label` | `assigned:agent-session` | Label that marks an issue as claimed. Must start with `assigned:` |
| `data_dir` | `~/.claude/dnbg` | Directory `findings_dir` and `retrospective_dir` sit under when not set on their own. Absolute or under `~/` |
| `findings_dir` | `<data_dir>/findings` | Where agents write what their reports found about the code. Absolute or under `~/` |
| `retrospectives` | off | On: each agent writes a file on where the process slowed it when its work ends. Off: it reports in chat only where a skill was wrong or had to be worked around |
| `retrospective_dir` | `<data_dir>/retrospectives` | Where those files go. Absolute or under `~/` |
| `version_stamp` | off | On: PR descriptions, reviews and issue claim comments end with a hidden `<!-- dnbg-workflow <version> -->` |
| `setup_notice` | on | On: each session opens with a one-line notice while `/dnbg-workflow:setup` still has something open, such as no accounts or no reviewer bot |

#### `velocity-tradeoff`

Off by default. When enabled, agents favor velocity over safety. For example,
they ship a whole capability in one PR, with no backwards-compatibility or
migration shims, where they would otherwise split the work into safer steps.
Useful where a bad change is cheap to undo, such as a project that is not yet
live or one that can tolerate brief disruption.

Enable per repo by adding the following to the repo's `CLAUDE.md`:

```markdown
## How to size a change here

Load `dnbg-workflow:velocity-tradeoff` when sizing a change or deciding
whether to split a PR. This repo has opted in, and only the operator ends
that.
```

### `dnbg-agent-summaries`

Edit with `/plugin configure dnbg-agent-summaries`.

| Setting | Default | Controls |
| --- | --- | --- |
| `data_dir` | `~/.claude/dnbg` | Directory `summary_dir` sits under when not set on its own. Absolute or under `~/` |
| `summary_dir` | `<data_dir>/agent-summaries` | Where agents write summary files. Absolute or under `~/` |

`data_dir` is set per plugin. To move every dnbg directory, set it to the same
value here and in `dnbg-workflow`.

### `dnbg-work-summary`

Edit with `/plugin configure dnbg-work-summary`.

| Setting | Default | Controls |
| --- | --- | --- |
| `owners` | empty | GitHub orgs and logins, comma-separated, whose repos a recap searches. Empty: it asks each time. Separate from `dnbg-workflow`'s `owners` |

## Agent roles

Each role posts under its own GitHub App once `/dnbg-workflow:reviewer-setup`
has created one. On every further machine the same skill connects to that App
with a key of the machine's own.

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

`/dnbg-workflow:reviewer-setup` saves each bot's key to
`~/.config/dnbg/<role>/private-key.pem`, plaintext, mode `0600`. Most installs
need nothing more.

There are two alternatives. Either one, when set, is used ahead of the file:

| To | Set | Notes |
| --- | --- | --- |
| Keep the key in a secret manager | `DNBG_<ROLE>_PRIVATE_KEY_COMMAND`, or `private_key_command` in `config.json` | A command that prints the key, such as `op read` or `pass show`. Move the key into the manager yourself. The command runs on every write, so one that prompts will prompt often |
| Run in CI | `DNBG_<ROLE>_PRIVATE_KEY`, with `DNBG_<ROLE>_APP_ID` | The key itself, so no file is needed. Every process you own can read it, so keep it off your own machine |

With both set, `DNBG_<ROLE>_PRIVATE_KEY` wins. A key from either alternative is
never written to disk. A config directory or key file that is group- or
world-writable is refused.
