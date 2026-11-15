A role's close-out after its work ends is now a few script calls instead of a
string of hand-run steps. `post-merge.sh` does the author's whole post-merge
cleanup in one call: it reads the PR's state, removes the branch's worktree
wherever it is, fast-forwards the default branch, and deletes the local and
remote branches as the repo's settings require. If one step fails, the rest
still run, and the result line names the step that failed.

With retrospectives on, `write-retrospective.sh` writes the retrospective file.
Its `--begin` form prints the prompt to answer, and the call after it reads the
run's usage, writes the file with its frontmatter, and posts the `Usage:`
comment. The file's layout and the comment's format are unchanged, so
`process-review` reads the new files as it read the old ones.
