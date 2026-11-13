New plugin: small conveniences for the session itself, on any forge. Install it
alone with `claude plugin install dnbg-comforts@dnbg`, or through `dnbg-all`.
Needs Claude Code v2.1.311 or newer.

- `/later <note>` leaves Claude a note it reads on its next turn, without
  starting a turn now.
- A dim band above the prompt shows context fill and where auto-compact runs,
  your plan's usage windows with their resets, and an estimate of how long the
  prompt cache stays warm, highlighted once it is cold. Off a subscription it
  shows the session's cost instead. It refreshes on its own and spends no
  tokens doing it.
- When the session runs on a model other than your standard one, the band names
  it: red when it costs more, blue when it costs less. You are also notified
  when the model saved for future sessions changes to another. Set your
  standard with `/plugin configure dnbg-comforts` (default `opus`).
- The band says when a plugin update is downloaded and waits for a restart.
- Before each compaction the transcript is copied to
  `~/.claude/dnbg/transcripts/<session id>/`. The copies are kept until you
  delete them.
