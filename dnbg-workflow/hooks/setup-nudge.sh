#!/usr/bin/env bash
# SessionStart hook: point the user at the `setup` skill while the setup check
# reads `setup=incomplete`. A fresh install is otherwise told nothing.
#
# It prints a `systemMessage`, which Claude Code shows to the user and keeps
# out of the model's context, where this hook's plain stdout would go the other
# way (both observed on v2.1.311). So it costs a session no tokens, and a
# session with no user is told nothing.
#
# Incomplete can be where the user means to stay, with no accounts or no
# reviewer App, so the `setup_notice` option turns the notice off. An option
# nobody set exports nothing here, which is on.
set -u

case "${CLAUDE_PLUGIN_OPTION_SETUP_NOTICE:-}" in [Ff][Aa][Ll][Ss][Ee]) exit 0 ;; esac

RESULT=$("$(dirname "$0")/../scripts/setup-check.sh" \
  --owners="${CLAUDE_PLUGIN_OPTION_OWNERS:-}" 2>/dev/null) || RESULT=""
case "$RESULT" in *$'\n'"result=OK setup=incomplete "*) ;; *) exit 0 ;; esac

# Claude Code prints the message in grey, which is easy to read past, and passes
# ANSI colour through to the terminal (observed on v2.1.311). Only the terminal
# client is known to render it, so every other entry point gets plain text.
MSG='NOTICE: Run /dnbg-workflow:setup to finish configuration.'
if [ "${CLAUDE_CODE_ENTRYPOINT:-}" = cli ] && [ -z "${NO_COLOR:-}" ]; then
  MSG="\\u001b[1;33m$MSG\\u001b[0m"
fi
printf '{"systemMessage":"%s"}\n' "$MSG"
exit 0
