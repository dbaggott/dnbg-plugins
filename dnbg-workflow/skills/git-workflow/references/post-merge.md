# Git workflow: after a merge

Part of the `git-workflow` skill. Read this when a PR merges: the merge watch
reports it, or you are told it merged, including in a session that never
handled a review round.

## After a merge

Any time the operator says something about the merge — kicking it off
("merging", "auto-merge is on", "go ahead") **or asserting it is done**
("merged", "it is merged", "done") — **verify state before acting on the
words**. Operators use "merged" for both "the button was clicked, auto-merge is
queued" and "GitHub shows merged"; same phrasing, different states. The cleanup
script reads the state itself, so run it from any checkout of the repo:

```bash
"<skill-dir>/../../scripts/post-merge.sh" <owner>/<repo> <num>
```

- **`result=NOT-MERGED state=CLOSED`** — nothing was removed, which leaves the
  worktree in case they reopen; close out as "Then close out" below says.
- **`result=NOT-MERGED state=OPEN auto_merge=scheduled`** — auto-merge is
  scheduled and a running watch will catch it.
- **`result=NOT-MERGED state=OPEN auto_merge=none`** — either they were being
  forward-looking or it has not merged. Say so; don't start a second watch.
- **`result=OK`** — merged, and the cleanup is done: the branch's worktree
  removed, wherever it is, the main checkout switched to the default branch
  and fast-forwarded, the local branch deleted, and the remote one deleted as
  the author when the repo does not delete it on merge. If a watch is still in
  flight it will report `CLOSED state=MERGED` shortly; ignore the duplicate
  rather than cleaning up twice.
- **`result=FAILED failed=<step,…>`** — merged, and the steps it names did not
  finish, each on a `step=<name> result=failed` line above it, with git's own
  error on stderr. Every other step ran. Finish those by hand before starting
  any new work.

The cleanup comes **before any new work**, as does the run on a merge the watch
in `references/merge-wait.md` reports as `CLOSED state=MERGED`.

### Then close out

The merge or the close without one ends your part of the work: close out. Report
per `<skill-dir>/../findings-review/references/report.md`, a delta against the
handoff report `references/merge.md` gave, with Summary opening with the PR's
full URL and the cleanup, or the close. Close out per
`<skill-dir>/../process-review/references/retrospective.md`, "When a
retrospective is written", with `role: author`. With retrospectives on, that is
`"<skill-dir>/../../scripts/write-retrospective.sh" --begin`, followed as it
prints.
