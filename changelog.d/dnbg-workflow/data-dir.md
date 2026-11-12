Retrospectives and findings entries now live under one directory,
`~/.claude/dnbg/`, as `retrospectives/` and `findings/`, instead of
`~/.claude/dnbg-retrospectives/` and `~/.claude/dnbg-findings/`. A new
`data_dir` setting moves both at once; `retrospective_dir` and `findings_dir`
still override either one.

The old directories are no longer read. If yours hold entries, each new session
shows a notice with the command that moves them; run it and the notice stops.
A `retrospective_dir` or `findings_dir` you set yourself is unaffected.
