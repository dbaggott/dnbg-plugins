# dnbg-plugins

An opinionated software factory, packaged as a set of Claude Code plugins. AI-driven and human-directed: think of it as an engineering team you lead, at whatever scale you run it.

I’ve spent over 25 years in software, including leading projects and teams and rebuilding entire tech organizations around a virtuous cycle, where past work informs current work and each step makes the next one easier and better. I built these plugins to work the same way: built-in retrospectives log friction as you go, and periodic sweeps turn the patterns into fixes.

Honed over its first 7 months of real use across 35 repos, ~2k PRs, ~1k issues, 1.2M+ lines of code, and 10 languages. Still sharpening.

**Quick start.** Run these in a terminal:

```
claude plugin marketplace add dbaggott/dnbg-plugins
claude plugin install dnbg-all@dnbg
claude
```

It needs Claude Code v2.1.207 or newer, and v2.1.299 for `dnbg-comforts` ([requirements](docs/requirements.md)). Native and npm installs update themselves; Homebrew and other package-manager installs don't by default, so upgrade those first (`brew upgrade claude-code`, or `claude-code@latest` if that is the cask you installed).

Then run `/dnbg-workflow:setup` in the session. It guides you through the rest. Nothing is enforced until you choose which repos it applies to.

## Opinions

**Crash-only agents.** State lives on GitHub: code, decisions, plans, claims and reviews. Any session can be cleared and restarted from a URL. Handoffs and issues carry everything the next agent needs, and nothing more.

**Human attention is the scarce resource.** Agents don’t tire. Humans do. Agents surface decisions faster than a person can make them well, and tired decisions are bad ones. Humans decide approach, what counts as done, and which deviations are acceptable. Findings and decisions are parked durably, so you can close an agent and triage later with fresh eyes. Nothing forces a decision before you’re ready.

**Quality is built in, not inspected in.** Review starts upstream, with the design and the issue specs, where human attention matters most. Agents review every PR. Humans make every merge, and they review the review when something warrants it. Roles are separate, so no agent reviews its own work. Every role can post to GitHub under its own identity. Hooks enforce the flow rather than suggest it.

**Tokens are a first-class concern.** Context grows fast and is expensive. Work is scoped tightly, and agents load only what the task needs. Nothing polls from inside an agent. The system calls for restarts before context gets costly. Usage is measured, so optimization is empirical.

**Concurrency is a given.** Many sessions and agents run at once. Each works in isolation and claims what it touches. Collisions are designed away.

**Friction is feedback unless it’s silent.** Agents quietly burn tokens and time on friction nobody sees. Opt in, and every role ends with a retrospective that makes it visible. Built-in tools find the patterns and turn them into issues. It’s how these plugins have been honed, and how you can help sharpen them.

**Join the flow anywhere.** The full flow takes an idea from design to merged code, but you can join at any point: a quick one-off change, a single issue, or a multi-week project. Enforcement applies only where you turn it on. See [The flow](#the-flow).

## The flow

Each stage runs in a fresh session, started from a prompt and a URL. Nothing carries over in a session’s memory: the next one reads what it needs from GitHub, so context stays small and any session can be closed or replaced.

| Stage | What happens | Prompt |
| --- | --- | --- |
| Design | You describe the work. If it’s more than one issue’s worth, the session offers to file it as a tracking issue: goals, constraints, decisions with their rationale and reversal conditions, and open questions with defaults. The reviewer bot reviews it in rounds. | `I want to plan out <the work>. File an issue for it.` |
| Accept | Once the review reads `READY`, the same session asks whether you accept the design. | answer its question |
| Decompose | The design is split into sub-issues with dependencies tracked in GitHub. The set is reviewed against the design for gaps and drift. | `decompose <URL>` |
| Execute | An orchestrator works the issues in dependency order, a few at a time, dispatching an author for each and a reviewer once its PR is sent to review. The reviewer re-reviews every push until the PR merges. | `orchestrate <URL>` |
| Close out | The orchestrator opens a closeout PR that writes the as-built design into the repo. You settle each finding the project left behind, the reviewer grades the whole project against the design’s acceptance criteria, and merging it closes the tracking issue. | merge the closeout PR |

Every stage ends by naming the next prompt. `where is <URL>` tells you where you are. A long-running orchestrator asks you to start a fresh one when its context has grown.

You’re called in where a human is worth the most: approving the design, answering what the design doesn’t settle, deciding what becomes of each finding, and merging. Everything else waits for you or runs without you.

The design and issue reviews run without you too: the session that wrote the issue starts a reviewer in the background and answers its rounds. To talk to the reviewer yourself, choose to run it in a session of your own, with `review <URL> as a spec`.

## Use cases

In the repos you’ve [configured](#setup):

| Say | What happens |
| --- | --- |
| *add a `--json` flag to the export script* | A worktree, the change, a self-review, a draft PR, and an offer to send it to review |
| *review `<PR URL>`*, in a second session | The reviewer bot reviews the PR, then re-reviews each push until it merges |
| *file an issue for the race in the retry path* | A self-contained issue with verified anchors and a proposed approach, then an offer to spec-review it |
| *review `<issue URL>` as a spec* | The reviewer bot reviews the issue in rounds, answered by the session that wrote it, until it reads `READY` |
| *resolve `<issue URL>`* | The issue is claimed, checked for freshness, reviewed critically, then resolved through a PR |
| *orchestrate `<issue URL>`* | An author and a reviewer are dispatched; questions the issue answers are answered, the rest come to you. It stops when you merge |
| *where is `<issue URL>`* | The current stage and the exact prompt to paste next |
| *summarize this week* | A recap of your merged PRs and filed issues, for the audience you name |
| *review the findings* | What the agents noticed about the code along the way, each one filed, dropped or kept with you |
| *review the retrospectives* | The friction patterns across runs, with upstream issues drafted for your approval |

Nothing reviews a PR until a reviewer is started: in a second session as above, or by `orchestrate`, which dispatches its own. A bare *review `<issue URL>`* could mean the issue or the PRs that resolve it, so you’ll be asked which.

## Setup

Runs on macOS or Linux, with GitHub as the forge ([details](docs/forge-support.md)).

`/dnbg-workflow:setup` shows how your install is set up, after walking you through only what’s still needed:

- **Your repos.** Which GitHub orgs or logins should use the workflow. None do, until you say.
- **The reviewer bot.** A GitHub App you create in the browser and install on the repos you choose. Its key stays on your machine.

It finishes with one list of every setting, what it is now and how to change it, the optional ones such as retrospectives and auto-update included. Stop whenever you like, and run it again at any time to look at your setup or to change an answer.

**Taking only part of it.** `dnbg-all` installs all five plugins. To take less, install any of `dnbg-workflow@dnbg`, `dnbg-practices@dnbg`, `dnbg-work-summary@dnbg`, `dnbg-agent-summaries@dnbg` or `dnbg-comforts@dnbg`; none requires another. Only `dnbg-workflow` has a setup step.

[`docs/configuration.md`](docs/configuration.md) lists every setting.

## What's in it

| Skill | Plugin | Forge | For |
| --- | --- | --- | --- |
| `git-workflow` | `dnbg-workflow` | GitHub only | Worktree, draft PR, review, merge and cleanup, end to end |
| `issue-workflow` | `dnbg-workflow` | GitHub only | Writing issues that survive a cold handoff; claiming and resolving one |
| `issue-reviewer` | `dnbg-workflow` | GitHub only | Reviewing an issue body as a spec, in rounds, before anyone picks it up |
| `reviewer` | `dnbg-workflow` | GitHub only | Reviewing a pushed PR under an independent GitHub App identity |
| `reviewer-setup` | `dnbg-workflow` | GitHub only | One-time creation of each role’s App, and connecting another machine to it |
| `setup` | `dnbg-workflow` | GitHub only | Checking what an install still needs and walking you through only that |
| `orchestrate` | `dnbg-workflow` | GitHub only | Driving an issue, a tracking issue’s children, or several issues to merged PRs with author and reviewer subagents |
| `project-status` | `dnbg-workflow` | GitHub only | Which stage of the flow an issue is at, and the prompt to paste next |
| `findings-review` | `dnbg-workflow` | GitHub only | Sweeping what agents found about the code, and filing, dropping or keeping each with you |
| `process-review` | `dnbg-workflow` | GitHub only | Finding patterns across agents’ retrospectives and drafting upstream issues |
| `velocity-tradeoff` | `dnbg-workflow` | **Any** | Opt-in: how to size work where the risk/benefit trade favors speed |
| `coding-practices` | `dnbg-practices` | **Any** | Design, security, naming, comments, logging and verification, as rules with IDs a review can cite |
| `work-summary` | `dnbg-work-summary` | GitHub only | Turning your merged and open PRs into an audience-shaped recap |
| `summary-review` | `dnbg-agent-summaries` | **Any** | Writing agent summary files with a status, and sweeping the stale ones into an archive |

Session comforts, in `dnbg-comforts`, which runs on any forge and needs Claude Code v2.1.299:

| Comfort | Does |
| --- | --- |
| `/later <note>` | leaves Claude a note it reads on its next turn, without starting one |
| Usage band | a dim line above the prompt: context fill and where auto-compact runs, your plan's usage windows with their resets, an estimate of how long the prompt cache stays warm (`none` before the first turn, yellow once cold), and the session's cost when you are not on a subscription |
| Model badge | in the band, any model other than your standard one: red when its family costs more, blue when it costs less, plain for another version of the same family |
| Saved-model notice | when the model saved for future sessions changes to one other than your standard, says so in a toast and, for 30 seconds, in the band |
| Update notice | in the band, plugins whose new version is downloaded and waits for a restart |
| Transcript copy | copies the transcript aside before each compaction, to `~/.claude/dnbg/transcripts/<session id>/`; the copies are kept until you delete them |

`dnbg-all` installs all five plugins.

Hooks, all in `dnbg-workflow`:

| Hook | Does |
| --- | --- |
| `inject-rules.sh` | puts the always-on rules in context at session start |
| `inject-rules-subagent.sh` | does the same for every subagent |
| `role-fallback-notice.sh` | names any role that will post as you |
| `setup-nudge.sh` | tells you that setup is not finished, until it is or you turn the notice off |
| `check-worktree.sh` | blocks edits to tracked files in a configured repo’s main checkout |
| `check-issue-create.sh` | blocks `gh issue create` in a configured repo until `issue-workflow` is loaded |

These hooks make no network calls, write no files and hold no credentials. They fail open: if a tool they need is missing, they stop protecting rather than stop you.

## Documentation

- [`docs/configuration.md`](docs/configuration.md): settings, agent roles and key handling
- [`docs/forge-support.md`](docs/forge-support.md): what each skill does outside GitHub
- [`docs/requirements.md`](docs/requirements.md): the Claude Code floor and command-line tools
- [`docs/releases.md`](docs/releases.md): updating and versioning
- [`docs/design/`](docs/design/): this repo’s own as-built designs, which double as worked examples
- [`SECURITY.md`](SECURITY.md): what installing grants, role App keys, reporting a vulnerability
- The skills under `dnbg-*/skills/`: they are the product, and the philosophy in full

## History

These plugins started at a startup I co-founded. We were building an AI product and took an AI-first stance: if AI couldn’t build our product, we weren’t confident a product built on AI could succeed. As a matter of discipline, we didn’t write or review any code ourselves. It quickly became clear that wasn’t viable without tooling around the agents. That tooling was the seed of this project.

## Contributing

Maintained by Dan Baggott. When something goes wrong, the agents will offer to file a bug for you. Please say yes. Issues are welcome; outside pull requests aren’t merged yet, since there’s no contributor agreement. Think an opinion is wrong? Make the case in an issue. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

Available under either of two licenses, at your option ([`LICENSE`](LICENSE)). PolyForm Internal Use 1.0.0 covers a company’s internal use, including while building products it sells, and allows changes for that use. PolyForm Strict 1.0.0 covers personal and hobby use, without changes. Neither allows distributing the plugins, so neither allows selling them.
