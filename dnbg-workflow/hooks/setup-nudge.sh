#!/usr/bin/env bash
# SessionStart hook: point the user at the `setup` skill while `owners` is
# empty, so nothing is enforced, or a role which refuses to fall back has no
# App, so nothing it posts can run. A fresh install is otherwise told neither.
#
# It prints a `systemMessage`, which Claude Code shows to the user and keeps
# out of the model's context, where this hook's plain stdout would go the other
# way (both observed on v2.1.311). So it costs a session no tokens, and a
# session with no user is told nothing.
#
# Empty `owners` is a legitimate end state, and so is going without a role's
# App, so each has an off switch: the marker file holds a line `owners` or
# `roles` once the user has said that one is unset on purpose. The `setup` skill
# appends them, at the path `setup-check.sh` prints. One acknowledged leaves the
# other still announced. Role state is `as-role.sh --roles`; any answer but its
# roles line, a missing `jq` included, is `role-fallback-notice.sh`'s or the
# dependency preflight's to report.
set -u

MARKER="${XDG_CONFIG_HOME:-${HOME:-}/.config}/dnbg/setup-acknowledged"
ACK=""
[ -r "$MARKER" ] && ACK=$(<"$MARKER")
acknowledged() {  # <owners|roles>
  case $'\n'"$ACK"$'\n' in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

OWNERS="${CLAUDE_PLUGIN_OPTION_OWNERS:-}"
OWNERS="${OWNERS//[[:space:],]/}"
[ -n "$OWNERS" ] || acknowledged owners || NUDGE=1

if [ -z "${NUDGE:-}" ] && ! acknowledged roles; then
  LINE=$("$(dirname "$0")/../scripts/as-role.sh" --roles 2>/dev/null) || LINE=""
  case "$LINE" in
    "result=OK configured="*" unconfigured=none") ;;
    "result=OK configured="*" unconfigured="*) NUDGE=1 ;;
  esac
fi
[ -n "${NUDGE:-}" ] || exit 0

# Claude Code prints the message in grey, which is easy to read past, and passes
# ANSI colour through to the terminal (observed on v2.1.311). Only the terminal
# client is known to render it, so every other entry point gets plain text.
MSG='NOTICE: Run /dnbg-workflow:setup to finish configuration.'
if [ "${CLAUDE_CODE_ENTRYPOINT:-}" = cli ] && [ -z "${NO_COLOR:-}" ]; then
  MSG="\\u001b[1;33m$MSG\\u001b[0m"
fi
printf '{"systemMessage":"%s"}\n' "$MSG"
exit 0
