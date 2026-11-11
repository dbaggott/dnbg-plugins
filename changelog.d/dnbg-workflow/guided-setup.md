New: `/dnbg-workflow:setup` checks what your install still needs and walks you
through only that. It covers which GitHub orgs or logins the workflow enforces
on, the reviewer bot, a missing command-line tool, a `gh` with no login and a
Claude Code older than the supported floor, then names the optional extras. Once
you name the accounts to enforce on, it offers to save the setting for you. Run
it again at any time to see what is left or to change an answer.

Behavior that changes under you: while `owners` is empty or the reviewer bot has
no GitHub App, a new session opens with a one-line message saying setup is not
finished. Until now neither was announced, so a fresh install enforced nothing
and could run no review without saying why. The message is shown to you and
costs the agent no context. If you mean to leave `owners` empty, say so in
`/dnbg-workflow:setup` and the message stops.
