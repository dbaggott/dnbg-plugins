Retrospectives and findings entries now live under one directory,
`~/.claude/dnbg/`, as `retrospectives/` and `findings/`, instead of
`~/.claude/dnbg-retrospectives/` and `~/.claude/dnbg-findings/`. A new
`data_dir` setting moves both at once; `retrospective_dir` and `findings_dir`
still override either one.

The old directories are no longer read. If yours hold entries, starting Claude
Code shows a notice with the command that moves them, and keeps showing it
until they are moved. The move never overwrites an entry already in the new
directory.
A `retrospective_dir` or `findings_dir` you set yourself is unaffected.
