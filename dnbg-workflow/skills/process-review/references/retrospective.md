# Process review: retrospectives

Part of the `process-review` skill, which reads retrospectives in batches to
find what recurs; this is the format they are written in, and the policy for
whether one is written at all. Each role reaches it at its close-out, which its
own skill names, whether a session dispatched it or not: the author once its PR
merges or closes, the PR reviewer when its review ends, both sides of a spec
review where it ends, the orchestrator at Stop and at each restart. Turns that
end earlier, such as the author's at send-to-review, write none. A
retrospective records where the **process** hurt one agent on one issue: the
skills, the scripts, the waits. A finding about the code the run built or
touched, such as a gap the design missed or a defect next to the work, is not a
retrospective item: it goes in a findings entry, per
`<skill-dir>/../findings-review/references/entry.md`, written with the report
that lists it.

`<skill-dir>` is the `process-review` skill's **Base directory**, or, for an
agent sent here by path, the directory holding this file's `references/`.

## When a retrospective is written

Retrospectives are **off**, unless a `dnbg-workflow` note at session start says
they are on. On answers the prompt `--begin` prints; off answers only the two
questions its branch names.

- **On**: write the file with `write-retrospective.sh`, at
  `<skill-dir>/../../scripts/write-retrospective.sh`. Its `--begin` prints a
  nonce, then "The prompt" below, which ends on the call that writes the file;
  the file's name and frontmatter are the script's, given in its header. The
  report names its path in a **Retrospective** section, with a dispatcher's
  also naming each path its agents' reports gave, and says nothing else about
  process friction. The
  always-on rule's offer to file upstream ("When shipped tooling
  doesn't fit, tell the user") is for friction that stopped the task from
  finishing; the rest waits in the file for `process-review`.
- **Off**: run no `write-retrospective.sh`, write no file, and give the report
  no **Retrospective** section. Answer these two questions from this run only:

  - **Skill wrong or missing**: what did a skill tell you that was wrong,
    missing, or contradicted by the tree? Name the skill and step, and quote the
    line.
  - **Worked around**: what did you work around?

  Under the report's **Observations**, put each answer as one line opening
  `Friction:`, naming what it is about. After those lines comes the
  always-on rule's offer to file upstream, with the operator approving the
  exact text first. With no answer to either question,
  there are no lines and no offer.

  A dispatched agent has no one to offer to: it puts the lines in its report
  and leaves the offer out. Its dispatcher relays them under its own
  Observations, and the offer is the main session's.

  "Asking the agents for one" below does not apply, and a dispatcher's report
  names no role as having left none: there is no file to ask for. Nothing from
  "The prompt" onward applies either, so stop reading here.

## The prompt

Answer from this run only, one `## ` heading per question, spelled and ordered
as here:

- **Slowed or blocked**: what slowed or blocked you?
- **Skill wrong or missing**: what did a skill tell you that was wrong, missing,
  or contradicted by the tree?
- **Worked around**: what did you work around?
- **Wished to ask**: what did you wish you could have asked?
- **Read but not used**: which reference files or sections did you read that
  this run did not need? One bullet per file, naming it.

Under them:

- **`Nothing.`** under a heading with nothing to report, since a clean run is
  data too. `process-review` groups by the headings.
- **One bullet per item, naming what it is about**: the skill and step, the
  reference file, or the script (`git-workflow` step 7, `watch-pr.sh`). Where a
  skill said something wrong, quote the line. Patterns are found by grouping on
  these names, so an item that names nothing cannot join one.
- **No secrets and no credentials.** The files are local, but `process-review`
  quotes them into issue drafts.

Write the five headings and their answers, and nothing else, to a file in your
draft directory (`git-workflow`'s `references/draft-files.md`). Then, in a Bash
call of its own, run the script again by the path you ran `--begin` by, given
the nonce it printed above this prompt:

```bash
"<script>" <nonce> --role=<role> --issue=<URL> --body=<file> [--root=<dir>]
```

- **`--role`** is the one your close-out names: `author`, `spec-author`,
  `reviewer`, `issue-reviewer` or `orchestrator`.
- **`--issue`** is the issue your run worked. A reviewer of a set of issues
  passes their parent. A set with no parent resolved by one PR
  (`orchestrate`'s `references/several-issues.md`) passes one `--issue` per
  issue. Work under no issue passes its PR's URL.
- **`--root`** is the retrospective root the session-start note names, when it
  names one. Without it the file goes under `~/.claude/dnbg/retrospectives`.

The script writes the file, and on a session's own usage posts the `Usage:`
comment on the issue as your role. Its result line names the file's `path=`, for
your report. `usage_comment=failed` means the file is written and the comment is
not: run `"<script>" --post-usage=<path>`. A
`result=ERROR` wrote nothing; fix what its `reason=` names and run it again.

## Asking the agents for one

With retrospectives on ("When a retrospective is written"), a session that
dispatched an agent, such as `orchestrate` or the spec review's spawned
reviewer, collects the agent's retrospective from its final report.
When that report names no retrospective path, or the path it gives does not
exist, continue that agent once with `SendMessage`:

> Write your retrospective now, per your close-out, and reply with the file's
> path.

That continuation is the fallback rather than the plan, because it replays the
agent's whole transcript for one more turn, and a late one finds the cache cold.

A dispatch cut off by a restart of its dispatcher leaves no retrospective, and
so does an agent replaced after dying on an error. Nothing can reach the old
agent, so the loss is not recovered. Say in your own final report which roles
have none. The usage of an agent a restart cut off survives in the restarting
orchestrator's `children`.
