Sending a PR to review now tells you where the review comes from. Outside
`orchestrate`, nothing starts a reviewer for you, and the session used to mark
the PR ready and wait half an hour in silence. It now ends that turn with the
prompt to paste into a new session, `review <PR URL>`, and the message you get
when no review arrives names the same prompt.

When no reviewer bot is set up, filing an issue and handing a design or a decomposed
set to review offer `reviewer-setup` instead of starting a reviewer that fails,
and sending a PR to review names `reviewer-setup` before the prompt.
