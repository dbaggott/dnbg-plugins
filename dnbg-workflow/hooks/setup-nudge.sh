#!/usr/bin/env bash
# SessionStart hook: tell the user, while either is true, that `owners` is empty,
# so nothing is enforced, or that a role which refuses to fall back has no App,
# so nothing it posts can run. A fresh install is otherwise told neither.
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

OPEN=""
[ -z "$OWNERS" ] && OPEN="\`owners\` is not set, so nothing is enforced"
[ "$UNCONFIGURED" != none ] &&
  OPEN="${OPEN:+$OPEN; }no GitHub App is set up for the ${UNCONFIGURED//,/, } role, so what it posts, such as a review, cannot run"
[ -n "$OPEN" ] || exit 0

# Built without `jq`: the text is fixed apart from role names, which
# `role_valid` holds to lowercase letters, digits and hyphens.
printf '{"systemMessage":"dnbg-workflow setup is not finished: %s. Run /dnbg-workflow:setup to finish it, or to say you are leaving it this way."}\n' "$OPEN"
exit 0
