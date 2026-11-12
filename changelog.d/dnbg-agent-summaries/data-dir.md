Summary files now default to `~/.claude/dnbg/agent-summaries/` instead of
`~/.claude/dnbg-agent-summaries/`, under a new `data_dir` setting shared in name
and default with `dnbg-workflow`. A `summary_dir` you set yourself is unaffected.

The old directory is no longer read. If it holds files, `summary-review` tells
you so and gives you the command that moves them.
