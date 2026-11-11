New: `/dnbg-workflow:setup` checks what your install still needs and walks you
through only that. It asks which GitHub accounts the workflow applies to and
saves your answer, offers to create the reviewer, author and orchestrator bots,
and flags a missing command-line tool, a `gh` with no login or a Claude Code
older than the supported floor. It ends on a summary of where setup stands and
the optional extras. Run it again at any time to see what is left, or
`/dnbg-workflow:setup owners` to change the accounts.

Behavior that changes under you: while no account is set or the reviewer bot
has no GitHub App, a new session opens with a one-line notice pointing at
`/dnbg-workflow:setup`. Until now neither was announced, so a fresh install
enforced nothing and could run no review without saying why. The notice is
shown to you and costs the agent no context. If you mean to leave the accounts
empty, say so in `/dnbg-workflow:setup` and the notice stops.

Creating the bots is smoother. The browser pages are restyled, a run that
creates several bots ends on one page with an install button for each, and that
page says how to choose which repos a bot is installed on. The agent no longer
narrates where keys are stored.
