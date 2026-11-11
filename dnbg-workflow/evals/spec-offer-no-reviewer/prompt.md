---
description: Whether filing a plain issue with no reviewer bot set up ends on `reviewer-setup` rather than on a spec-review prompt that cannot run. The filing is given as done, since the run has no authenticated `gh`; the reviewer read is the run's own, and answers `not-configured` because the run's `HOME` holds no reviewer App. Run it with `XDG_CONFIG_HOME` and every `DNBG_REVIEWER_*` variable unset: one that reaches a reviewer's configuration makes the read answer `OK`, and both arms score 0.
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

You have just filed a plain issue in `acme/widgets` on its own, through `issue-workflow`'s `references/filing.md`, "File it": `gh issue create` printed https://github.com/acme/widgets/issues/110. Do what `references/filing.md` has you do next, and end with your report.

One fact about this environment: there is no network, so make no `gh` call.
