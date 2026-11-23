#!/usr/bin/env bash
# PreToolUse hook: block `write-retrospective.sh`, in any of its forms, while
# the `retrospectives` option is off. Plugin options reach hooks only, so the
# script cannot check the setting itself, and an agent that misreads its state
# would otherwise write a file and post a `Usage:` comment that off rules out.
#
# Exit 0 = allow. Exit 2 = block; stderr is shown to the agent.

set -e
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

retrospectives_enabled && exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

[ "$TOOL" = "Bash" ] || exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# The skills run the script by a quoted path, so that is the word kept from
# masking. An interpreter in front of it is an invocation too.
invokes_command "$CMD" write-retrospective.sh \
  '((ba)?sh[[:space:]]+)?[^[:space:];&|()]*write-retrospective\.sh([[:space:];&|)]|$)' || exit 0

cat >&2 <<'EOF2'
BLOCKED by dnbg-workflow:check-retrospectives — retrospectives are off, so
`write-retrospective.sh` does not run in any form. Nothing in this Bash call
ran.

Run the rest of the command again without the script, if there was a rest.
Then close out per `process-review`'s `references/retrospective.md`, "When a
retrospective is written", the Off branch: no file, no Usage comment.
EOF2
exit 2
