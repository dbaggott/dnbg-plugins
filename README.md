# dnbg-plugins

An opinionated software factory, packaged as a set of Claude Code plugins. AI-driven and human-directed: think of it as an engineering team you lead, at whatever scale you run it.

I’ve spent over 25 years in software, including leading projects and teams and rebuilding entire tech organizations around a virtuous cycle, where past work informs current work and each step makes the next one easier and better. I built these plugins to work the same way: built-in retrospectives log friction as you go, and periodic sweeps turn the patterns into fixes.

Honed over its first 7 months of real use across 35 repos, ~2k PRs, ~1k issues, 1.2M+ lines of code, and 10 languages. Still sharpening.

**Quick start.** Run these one at a time in Claude Code:

```
/plugin marketplace add dbaggott/dnbg-plugins
```

```
/plugin install dnbg-all@dnbg
```

Then see [Setup](#setup).

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
| Design | You describe the work. If it’s more than one issue’s worth, the session offers to file it as a tracking issue: goals, constraints, decisions with their rationale and reversal conditions, and open questions with defaults. The reviewer bot reviews it in rounds. | `I want to <the work>. File an issue for it.` |
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

**Install.** Run these one at a time in Claude Code:

```
/plugin marketplace add dbaggott/dnbg-plugins
```

```
/plugin install dnbg-all@dnbg
```

`dnbg-all` installs all four plugins. To take less, install any of `dnbg-workflow@dnbg`, `dnbg-practices@dnbg`, `dnbg-work-summary@dnbg` or `dnbg-agent-summaries@dnbg`; none requires another. The install asks for a scope: choose `user` for one person across many repos, or `project` for one repo shared with a team ([details](docs/configuration.md#install-scope)).

Installed before the plugins moved to this repo? Run `/plugin marketplace remove dnbg`, then both commands above.

**Configure your repos.** Set `owners` to the GitHub orgs or logins whose repos should use the workflow: run `/plugin configure dnbg-workflow`. In those repos, editing a tracked file in the main checkout is blocked, and so is `gh issue create` until the issue skill is loaded. Until you set `owners`, nothing is enforced and the workflow is only advice.

**Give the agents their identities.** Ask Claude Code to *set up the reviewer bot*. It creates a GitHub App per role on your account: you click **Create GitHub App** in the browser for each, then install it on the accounts and repos it should work in. The keys stay on your machine. The reviewer App is required for reviews. The author and orchestrator Apps are optional and fall back to your account.

**Keep it current.** Enable auto-update (`/plugin`, then **Marketplaces**, **dnbg**, **Enable auto-update**), or run `/plugin marketplace update dnbg`. See [releases](docs/releases.md).

**Everything else is optional.** Only `owners` turns on enforcement. Turn on `retrospectives` the same way to have every role record its friction. [`docs/configuration.md`](docs/configuration.md) covers every setting and why its default is what it is.

## What's in it

| Skill | Plugin | Forge | For |
| --- | --- | --- | --- |
| `git-workflow` | `dnbg-workflow` | GitHub only | Worktree, draft PR, review, merge and cleanup, end to end |
| `issue-workflow` | `dnbg-workflow` | GitHub only | Writing issues that survive a cold handoff; claiming and resolving one |
| `issue-reviewer` | `dnbg-workflow` | GitHub only | Reviewing an issue body as a spec, in rounds, before anyone picks it up |
| `reviewer` | `dnbg-workflow` | GitHub only | Reviewing a pushed PR under an independent GitHub App identity |
| `reviewer-setup` | `dnbg-workflow` | GitHub only | One-time creation of each role’s App |
| `orchestrate` | `dnbg-workflow` | GitHub only | Driving an issue, a tracking issue’s children, or several issues to merged PRs with author and reviewer subagents |
| `project-status` | `dnbg-workflow` | GitHub only | Which stage of the flow an issue is at, and the prompt to paste next |
| `findings-review` | `dnbg-workflow` | GitHub only | Sweeping what agents found about the code, and filing, dropping or keeping each with you |
| `process-review` | `dnbg-workflow` | GitHub only | Finding patterns across agents’ retrospectives and drafting upstream issues |
| `velocity-tradeoff` | `dnbg-workflow` | **Any** | Opt-in: how to size work where the risk/benefit trade favors speed |
| `coding-practices` | `dnbg-practices` | **Any** | Design, security, naming, comments, logging and verification, as rules with IDs a review can cite |
| `work-summary` | `dnbg-work-summary` | GitHub only | Turning your merged and open PRs into an audience-shaped recap |
| `summary-review` | `dnbg-agent-summaries` | **Any** | Writing agent summary files with a status, and sweeping the stale ones into an archive |

`dnbg-all` installs all four plugins.

Hooks, all in `dnbg-workflow`:

| Hook | Does |
| --- | --- |
| `inject-rules.sh` | puts the always-on rules in context at session start |
| `inject-rules-subagent.sh` | does the same for every subagent |
| `role-fallback-notice.sh` | names any role that will post as you |
| `check-worktree.sh` | blocks edits to tracked files in a configured repo’s main checkout |
| `check-issue-create.sh` | blocks `gh issue create` in a configured repo until `issue-workflow` is loaded |

The hooks make no network calls, write no files and hold no credentials. They fail open: if a tool they need is missing, they stop protecting rather than stop you.

## Documentation

- [`docs/configuration.md`](docs/configuration.md): settings, install scope, agent roles and key handling
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
