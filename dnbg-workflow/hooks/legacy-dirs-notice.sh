#!/usr/bin/env bash
# SessionStart hook: tell the user when retrospectives or findings entries are
# still in the directories they were written to before both moved under the data
# directory, with the command that moves them. Nothing reads the old ones.
#
# A `systemMessage`, as in setup-nudge.sh: the user sees it, the model does not,
# and the user runs the move, since it touches files outside any repo.
set -u
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

# Only an install that never set its own directory wrote to these, so they are
# fixed paths, not settings.
MSG=""
for pair in "${HOME:-}/.claude/dnbg-retrospectives|$(resolve_retrospective_dir)" \
            "${HOME:-}/.claude/dnbg-findings|$(resolve_findings_dir)"; do
  MOVE=$(legacy_dir_move "${pair%%|*}" "${pair#*|}")
  MOVE=${MOVE//\\/\\\\}
  MOVE=${MOVE//\"/\\\"}
  [ -n "$MOVE" ] && MSG="${MSG:+$MSG\\n}  $MOVE"
done
[ -n "$MSG" ] || exit 0

MSG="NOTICE: dnbg-workflow no longer reads these directories. Move their entries with:\\n$MSG"
printf '{"systemMessage":"%s"}\n' "$MSG"
exit 0
