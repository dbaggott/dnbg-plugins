With retrospectives off (the default), a close-out no longer writes a
retrospective file or posts a `Usage:` comment. A new hook blocks the
retrospective script whenever the `retrospectives` option is not `true`, and the
session-start note now says outright that retrospectives are off.

An off-mode close-out also costs less: the agent answers only the two questions
it reports as `Friction:` lines, instead of reading and answering the whole
retrospective prompt.
