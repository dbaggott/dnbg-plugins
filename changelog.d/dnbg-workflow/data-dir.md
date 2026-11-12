Retrospectives and findings entries now live under one directory,
`~/.claude/dnbg/`, as `retrospectives/` and `findings/`, instead of
`~/.claude/dnbg-retrospectives/` and `~/.claude/dnbg-findings/`. A new
`data_dir` setting moves both at once; `retrospective_dir` and `findings_dir`
still override either one.

The old directories are no longer read. Move any entries in them to the new
ones to keep them in `findings-review` and `process-review`. A
`retrospective_dir` or `findings_dir` you set yourself is unaffected.
