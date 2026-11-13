#!/usr/bin/env bash
# SessionStart hook: while the setup check reads `setup=incomplete`, tell the
# user to update Claude Code when the client is below the floor, and otherwise
# point them at the `setup` skill. A fresh install is otherwise told nothing.
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

# The rest of setup is told once the client is new enough to run it. On a
# Homebrew or other package-manager install, `claude update` names the command
# that updates it.
BELOW=$'(^|\n)check=claude-code state=below version=([0-9.]+) floor=([0-9.]+)'
if [[ "$RESULT" =~ $BELOW ]]; then
  MSG="NOTICE: dnbg needs Claude Code ${BASH_REMATCH[3]} or newer, and this is ${BASH_REMATCH[2]}. Run \`claude update\` in a terminal."
else
  MSG='NOTICE: Run /dnbg-workflow:setup to finish configuration.'
fi

# Claude Code prints the message in grey, which is easy to read past, and passes
# ANSI colour through to the terminal (observed on v2.1.311). Only the terminal
# client is known to render it, so every other entry point gets plain text.
if [ "${CLAUDE_CODE_ENTRYPOINT:-}" = cli ] && [ -z "${NO_COLOR:-}" ]; then
  MSG="\\u001b[1;33m$MSG\\u001b[0m"
fi
printf '{"systemMessage":"%s"}\n' "$MSG"
exit 0
