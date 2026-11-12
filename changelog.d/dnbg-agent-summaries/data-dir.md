Summary files now default to `~/.claude/dnbg/agent-summaries/` instead of
`~/.claude/dnbg-agent-summaries/`, under a new `data_dir` setting shared in name
and default with `dnbg-workflow`. A `summary_dir` you set yourself is unaffected.

The old directory is no longer read. Move any files in it to the new one to keep
them in `summary-review`.
