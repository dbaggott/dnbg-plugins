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
# Silent once the marker exists: empty `owners` is a legitimate end state, and
# the marker is the user's answer that what remains is unset on purpose. The
# `setup` skill writes it, at the path `setup-check.sh` prints. Role state is
# `as-role.sh --roles`; any answer but its roles line, a missing `jq` included,
# is `role-fallback-notice.sh`'s or the dependency preflight's to report.
set -u

MARKER="${XDG_CONFIG_HOME:-${HOME:-}/.config}/dnbg/setup-acknowledged"
[ -e "$MARKER" ] && exit 0

OWNERS="${CLAUDE_PLUGIN_OPTION_OWNERS:-}"
OWNERS="${OWNERS//[[:space:],]/}"

UNCONFIGURED=none
LINE=$("$(dirname "$0")/../scripts/as-role.sh" --roles 2>/dev/null) || LINE=""
case "$LINE" in
  "result=OK configured="*" unconfigured="*) UNCONFIGURED="${LINE##* unconfigured=}" ;;
esac

[ -z "$OWNERS" ] || [ "$UNCONFIGURED" != none ] || exit 0

# Claude Code prints the message in grey, which is easy to read past, and passes
# ANSI colour through to the terminal (observed on v2.1.311). Only the terminal
# client is known to render it, so every other entry point gets plain text.
MSG='NOTICE: Run /dnbg-workflow:setup to finish configuration.'
if [ "${CLAUDE_CODE_ENTRYPOINT:-}" = cli ] && [ -z "${NO_COLOR:-}" ]; then
  MSG="\\u001b[1;33m$MSG\\u001b[0m"
fi
printf '{"systemMessage":"%s"}\n' "$MSG"
exit 0
