---
name: process-review
description: Read a batch of the retrospectives that agents leave behind, report the process patterns in them with counts and quoted examples and the usage by role, and draft upstream issues for the operator to approve. Load when asked to review the retrospectives, find process patterns, or say what keeps slowing the agents down. It reads the retrospective files, including their `usage` frontmatter, its own past reports, and the `_usage/` reports of the usage sweep, which it runs over the local session transcripts, never a tracking issue. Skip for writing a retrospective, which is this skill's `references/retrospective.md`, and for findings about the code, which are `findings-review`'s and a tracking issue's closeout's.
---

# Process review

A retrospective records where the process hurt one agent on one issue, and one
file is an anecdote. This finds what recurs across many, and drafts an upstream
issue for whatever the shipped tooling is to blame for. It runs cold: everything
it needs is in the files and this page.

The file format, including the five headings this groups by, is in this
skill's `references/retrospective.md`, at
`<skill-dir>/references/retrospective.md`. `<skill-dir>` is the **Base
directory** announced when this skill loads.

## 1. Gather the batch

The root is `~/.claude/dnbg-retrospectives/` by default, not a constant: if a
`dnbg-workflow` note at session start names a different retrospective root, use
that one. The batch is drawn from every `*.md` file under the root, recursively,
**except** under `<root>/_reviews/`, which holds this skill's own reports
(step 3), and under `<root>/_usage/`, which holds the usage sweep's reports. A run is one of three kinds, recorded as its report's `batch`:

- **`delta`**, the default when `_reviews/` holds a report whose `batch` is
  `delta` or `all`. Chain from the newest such report (by file name), ignoring
  subset reports: a subset run has not read the rest, so its reach is no
  watermark. The batch is:
  - every retrospective whose basename starts with a `<YYYY-MM-DD>T<HHMMSS>Z`
    prefix at or after that report's `newest`, comparing that prefix, not the
    full name, the frontmatter `date` or mtime. "At or after", so two files
    written in the watermark's second are not lost;
  - the files cited by that report's **Carried** singletons, so a singleton
    that recurs in the delta becomes a pattern with both sources in hand. A
    cited file that no longer exists goes under Unreadable as missing;
  - the files that report's Carried section lists as **Unreadable**, so a
    repaired file is counted once it reads;
  - any file whose basename has no such prefix: it goes under Unreadable with
    that reason, and so is carried and tried again next run.

  A file in more than one of these is read once. Beyond these, the files of
  carried **patterns** are not re-read; their sources and examples come from
  Carried.
- **`all`**, when `_reviews/` holds no `delta` or `all` report, or when the
  operator names `all`: every file under the root, with nothing carried in.
- **A subset** the operator names: a repo's `<owner>/<repo>/` directory, a list
  of files, a date range against the frontmatter `date`, or one
  `plugin_version`. Its `batch` is what was named. Nothing is carried in.

Read every file in the batch in full. A file missing `role` or `issue` in its
frontmatter, or missing any of the first four headings, goes under
**Unreadable** in the report with what it lacks, and counts toward nothing. A
file without `## Read but not used`, the fifth, was written before it existed:
it is readable, and contributes nothing under that heading. A file written before
a spec round's role became its own carries the PR role for a spec round too:
`reviewer` before `issue-reviewer`, `author` before `spec-author`. It is
readable, and counts under the role it carries. An
`issue:` that is a list names a set of issues, and its first URL is the file's
issue wherever this skill keys on `issue`.

Gather each readable file's `usage` and `children` frontmatter with its `role`
and `issue`, except, in a `delta` run, from a file the chained report already
counted: one whose prefix is not after that report's `newest`, unless its
Carried section lists the file as Unreadable. So a file stamped in `newest`'s
second but written after that run is not counted; that gap is the price of
never counting a file twice. Of the files whose usage is gathered, one with no
`usage`, or whose `usage` reads `result: UNKNOWN`, counts toward no usage figure
and is listed under `## Usage` (step 3) with that reason; a file not gathered
for usage is not listed. Either way it is still read for everything else.

Then run the usage sweep:

```bash
"<skill-dir>/../../scripts/usage-sweep.sh" --since=<since> --root=<root>
```

`<root>` is given as an absolute path, since no shell expands a `~` after
`=`. `<since>` is the date in the chained report's `newest` in a `delta` run, and
the date in the earliest basename prefix in the batch in an `all` or subset
run. It prints one line. After `result=OK report=<path>`, read the twin
beside that report, its `.md` replaced by `.json`. After `result=UNKNOWN
reason=<reason>`, which goes under `## Usage` with its reason, read the newest
`<root>/_usage/*.json` by file name instead, if there is one, an older sweep's.

## 2. Find the patterns

Group the items by heading, then within a heading put together the items that
describe one problem: the same skill step, script, or missing instruction, even
when worded differently.

- **The count is the number of sources carrying the problem.** A source is one
  role on one issue, all its files together. So one agent repeating itself
  counts once.
- **A pattern has a count of at least two.** Everything else is a singleton.
- **One problem under two headings is one pattern.** File it under the heading
  most of its sources use, and count each source once.
- **In a `delta` run, start from the chained report's Carried patterns.**
  Each keeps its carried statement, which is what its Filed line is matched by.
  Match each against the batch's items by that statement and its carried
  examples, and recompute its count over the union of its carried sources and
  the new ones, keyed by `role` plus `issue`: an item from a source already
  listed, such as a re-read singleton file, does not raise it. A carried
  singleton matched by an item from another source becomes a pattern.
- **Note the spread**: the roles, the issues, and the `plugin_version` values.
  When every source predates the current version, read the current text of the
  skill or script before proposing anything, since it may already be fixed. Say
  which you found.

## 3. Report

One section per heading that has anything, patterns in descending count. Each
pattern is a one-line statement of the problem, its count and spread, and two
examples quoted verbatim, each cited by file name:

```markdown
### Worked around

**`claim-issue.sh` reads a resumed session's own claim as `FOREIGN`, and the
agent re-claims over itself.** Count 2: author ×2; 2 issues; 2026.10.3.

> "claim-issue said FOREIGN with my own id after the resume, so I re-claimed."
> (`2026-09-30T101500Z-17-author.md`)

> "Re-claimed over what turned out to be my own claim."
> (`2026-10-02T143000Z-21-author.md`)
```

In the section for `## Read but not used`, items are put together by the file
each bullet names rather than by problem, and a pattern there is a **split
candidate**: its statement names the file, and its examples are two of the
bullets naming it.

After the per-heading sections comes **`## Usage`**, built from the gathered
records and the sweep, in raw counts:

- **By role**: one row per retrospective `role`, giving sessions (the files
  that contributed), `requests`, `input`, `cache_write`, `cache_read` and
  `output`, each summed over that role's `scope: self` records alone.
- **By session**: one row per `scope: session` record, keyed by `issue` and
  `role`, with its counts, and under it one sub-row per entry of the file's
  `children`, giving `agent`, `depth` and that entry's counts. Neither the row
  nor its sub-rows is added to any by-role row: each is a total over agents
  whose own `self` records count under their roles.
- **The previous tables**: under each table, the same table from the chained
  report's `## Usage` section, cited by that report's file name, or the words
  "no previous report" when there is no chained report or it has no such
  section.
- **The sweep**: the path of the `.md` report beside the twin step 1 read, its
  `range`, and the twin's `agents` rows quoted for `main` and for each agent
  type starting `dnbg-workflow:`, the plugin's own agents; and the sweep's
  `UNKNOWN` reason if it gave one. With no twin to read, say so.
- **No usage**: each file step 1 gathered without a usable `usage`, by file
  name, with its reason.

A weighted figure, such as a cost, is given only beside the sentence naming
its weights and the model they price.

After `## Usage`, list the singletons one line each, since the next batch can
make any of them a pattern. Then **Unreadable**, if anything was. In a `delta`
run, every carried pattern is in the report whether or not it gained a source:
one left out breaks the chain the next run reads, and a recurrence would count
as a fresh singleton.

Before drafting anything, write the report to
`<root>/_reviews/<YYYY-MM-DD>T<HHMMSS>Z.md`, stamped in UTC
(`date -u +%Y-%m-%dT%H%M%SZ`), so a run abandoned in step 4 still leaves it:

```markdown
---
tags:
  - process-review
date: <YYYY-MM-DD>
batch: <delta, all, or the subset named>
files: <count read>
newest: <the newest basename prefix in the batch, never earlier than the chained report's>
plugin_version: <as retrospective.md's plugin_version step sources it>
---
```

`<root>` is the root step 1 read from. Only a `delta` or `all` run writes
`newest`. The body is the report above, then:

- **`## Carried`**, in a `delta` or `all` run only: the state the next run reads. Every pattern and every
  singleton: its heading, its one-line statement, and its sources, one line per
  source giving `role`, `issue` and the file names it was found in. A pattern
  also keeps its two quoted examples; a singleton does not, since its files are
  re-read. Then the Unreadable file names. In an `all` run it is this run's
  findings alone. Usage is not carried: the next run reads this report's
  `## Usage` tables directly.
- **`## Filed`**, appended in step 4.

## 4. Draft upstream issues

The **last report** is the newest `delta` or `all` report under `_reviews/`
before this one, whatever kind this run is; in a `delta` run it is the chained
report. Draft only for a pattern that has a source the last report's Carried
does not list, or no decided line in its Filed section: none at all, or
`not filed: no operator (delegated)`. With no last report, every pattern is
drafted. A pattern that gets no draft copies its decided Filed line into this
report's Filed section, so the decision survives the next run.

For each such pattern caused by shipped tooling, meaning a skill, script, or hook of
an installed plugin rather than the project's own code or the operator's setup,
draft an issue under the always-on rule "When shipped tooling doesn't fit, tell
the user":

- **The destination** is the `repository` field of the owning plugin's
  `.claude-plugin/plugin.json`.
- **Check for an existing issue first.** The last report's Filed line for
  the pattern names its issue when one was filed, and the draft is a comment
  adding the new sources. Otherwise search with
  `gh issue list --repo <destination> --state all --search "<keywords>"`, which
  is also what finds an issue a subset run filed. When one covers the pattern,
  draft a comment adding the new evidence instead.
- **Write from the generic case.** Leave out repo names, issue URLs, file paths,
  and any quote that identifies the operator's work. Keep the count and the
  substance of the examples.
- **Shape the body** per `issue-workflow`'s `references/creating.md`.

A **usage pattern**, a change between this report's `## Usage` tables and the
chained report's, is drafted on judgement rather than a threshold until the
operator sets one, since no baseline exists before the first report. Its draft
quotes both tables and says what moved, and is decided and recorded like any
other draft.

Show the operator each draft's exact text, after the report. File one only once
the operator approves that exact text, and load `issue-workflow` before filing.
An edited draft is new text, which needs approval again. Never file without
that approval. Where `AskUserQuestion` is absent, as in a subagent, report the
drafts and file nothing.

As each draft is decided, append its line to the report's `## Filed` section:
the pattern's one-line statement, then the issue or comment URL,
`not filed: <the operator's reason>`, or, without `AskUserQuestion`,
`not filed: no operator (delegated)`.

When any draft was filed as a new issue in a covered repo, offer the spec
review for those issues, per `issue-workflow`'s `references/filing.md`, "Offer
the spec review for a batch". A draft filed anywhere else is a gap reported
upstream, and a comment on an existing issue is not a new one: neither is
offered.

Close with one line naming the report file written.
