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

**Crash-only agents.** State lives in source control: code, decisions, plans, claims and reviews. Any session can be cleared and restarted from a URL. Handoffs and issues carry everything the next agent needs, and nothing more.

**Human attention is the scarce resource.** Agents don’t tire. Humans do. Agents surface decisions faster than a person can make them well, and tired decisions are bad ones. Humans decide approach, what counts as done, and which deviations are acceptable. Findings and decisions are parked durably, so you can close an agent and triage later with fresh eyes. Nothing forces a decision before you’re ready.

**Quality is built in, not inspected in.** Review starts upstream, with the design and the issue specs, where human attention matters most. Agents review every PR. Humans make every merge, and they review the review when something warrants it. Each role has its own identity, and hooks enforce the flow rather than suggest it.

**Tokens are a first-class concern.** Context grows fast and is expensive. Work is scoped tightly, and agents load only what the task needs. Nothing polls from inside an agent. The system calls for restarts before context gets costly. Usage is measured, so optimization is empirical.

**Concurrency is a given.** Many sessions and agents run at once. Each works in isolation and claims what it touches. Collisions are designed away.

**Friction is feedback unless it’s silent.** Agents quietly burn tokens and time on friction nobody sees. Opt in, and every role ends with a retrospective that makes it visible. Built-in tools find the patterns and turn them into issues. It’s how these plugins have been honed, and how you can help sharpen them.

**Join the flow anywhere.** The full flow takes an idea from design to merged code, but you can join at any point: a quick one-off change, a single issue, or a multi-week project. Enforcement applies only where you turn it on. See [The flow](#the-flow).

## The flow

| Stage | What happens | Prompt |
| --- | --- | --- |
| Design | A tracking issue records goals, constraints, decisions with their rationale and reversal conditions, and open questions with defaults. The reviewer bot reviews it in rounds. | file the tracking issue, then `review <URL> as a spec` |
| Accept | You sign off the design. | `answer the spec review on <URL>` |
| Decompose | The design is split into sub-issues with dependencies tracked in GitHub. The set is reviewed against the design for gaps and drift. | `decompose <URL>` |
| Execute | An orchestrator works the issues in dependency order, dispatching an author and a reviewer for each. Every PR is reviewed on every push. | `orchestrate <URL>` |
| Close out | The finished work is checked against the design, and the as-built design is written into the repo. | merge the closeout PR |

Every stage ends by naming the next prompt. `where is <URL>` tells you where you are.

You’re needed to sign off the design, answer escalations, and merge. Everything else waits for you or runs without you.

## Use cases

In a repo covered by the gates:

| Say | What happens |
| --- | --- |
| *add a `--json` flag to the export script* | A worktree, the change, a self-review, a draft PR, and an offer to send it to review |
| *file an issue for the race in the retry path* | A self-contained issue with verified anchors and a proposed approach, then an offer to spec-review it |
| *review `<issue URL>` as a spec* | The reviewer bot reviews the issue in rounds until it reads `READY` |
| *resolve `<issue URL>`* | The issue is claimed, checked for freshness, reviewed critically, then resolved through a PR |
| *orchestrate `<issue URL>`* | An author and a reviewer are dispatched; questions the issue answers are answered, the rest come to you |
| *where is `<issue URL>`* | The current stage and the exact prompt to paste next |
| *summarize this week* | A recap of your merged PRs and filed issues, for the audience you name |

## Setup

Runs on macOS or Linux, with GitHub as the forge ([details](docs/forge-support.md)).

**Install.** Run these one at a time in Claude Code:

```
/plugin marketplace add dbaggott/dnbg-plugins
```

```
/plugin install dnbg-all@dnbg
```

`dnbg-all` installs all four plugins. To take less, install any of `dnbg-workflow@dnbg`, `dnbg-practices@dnbg`, `dnbg-work-summary@dnbg` or `dnbg-agent-summaries@dnbg`; none requires another. Choose `user` scope for one person across many repos, or `project` for one repo shared with a team ([details](docs/configuration.md#install-scope)).

Installed before the plugins moved to this repo? Run `/plugin marketplace remove dnbg`, then the install again.

**Turn the gates on.** Set `owners` to the GitHub orgs or logins you want enforced, in `/plugin`’s configuration for `dnbg-workflow`. In a covered repo, edits outside a worktree and `gh issue create` without the issue skill are blocked.

**Give the agents their identities.** Ask Claude Code to *set up the reviewer bot*. It creates a GitHub App per role on your account, and the keys stay on your machine. The reviewer App is required for reviews. The author and orchestrator Apps are optional and fall back to your account.

**Keep it current.** Enable auto-update (`/plugin`, then **Marketplaces**, **dnbg**, **Enable auto-update**), or run `/plugin marketplace update dnbg`. See [releases](docs/releases.md).

**Everything else is optional.** Only `owners` turns on enforcement. [`docs/configuration.md`](docs/configuration.md) covers every setting and why its default is what it is.

## What’s in it

| Plugin | Skills |
| --- | --- |
| `dnbg-workflow` | `git-workflow`, `issue-workflow`, `issue-reviewer`, `reviewer`, `reviewer-setup`, `orchestrate`, `project-status`, `findings-review`, `process-review`, `velocity-tradeoff` |
| `dnbg-practices` | `coding-practices` |
| `dnbg-work-summary` | `work-summary` |
| `dnbg-agent-summaries` | `summary-review` |
| `dnbg-all` | installs the four above |

Hooks, all in `dnbg-workflow`:

| Hook | Does |
| --- | --- |
| `inject-rules.sh` | puts the always-on rules in context at session start |
| `inject-rules-subagent.sh` | does the same for every subagent |
| `role-fallback-notice.sh` | names any role that will post as you |
| `check-worktree.sh` | blocks edits to tracked files in a covered repo’s main checkout |
| `check-issue-create.sh` | blocks `gh issue create` in a covered repo until `issue-workflow` is loaded |

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
