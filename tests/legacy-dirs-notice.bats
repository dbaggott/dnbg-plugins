#!/usr/bin/env bats
#
# Tests for the SessionStart notice about retrospectives and findings entries
# left in the directories used before the data directory. Each runs with its own
# HOME, so the developer's own directories decide nothing.

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../dnbg-workflow/hooks/legacy-dirs-notice.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  unset CLAUDE_PLUGIN_OPTION_DATA_DIR CLAUDE_PLUGIN_OPTION_RETROSPECTIVE_DIR \
    CLAUDE_PLUGIN_OPTION_FINDINGS_DIR
}

message() { jq -er '.systemMessage' <<<"$output"; }

@test "says nothing when no legacy directory holds entries" {
  mkdir "$HOME/.claude/dnbg-findings"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "names the move for each legacy directory that holds entries" {
  mkdir -p "$HOME/.claude/dnbg-retrospectives/acme/api" "$HOME/.claude/dnbg-findings/acme/api"
  touch "$HOME/.claude/dnbg-retrospectives/acme/api/r.md" "$HOME/.claude/dnbg-findings/acme/api/f.md"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(jq -c 'keys' <<<"$output")" = '["systemMessage"]' ]
  [[ "$(message)" == *"move-legacy-dir.sh\" \"$HOME/.claude/dnbg-retrospectives\" \"$HOME/.claude/dnbg/retrospectives\""* ]]
  [[ "$(message)" == *"move-legacy-dir.sh\" \"$HOME/.claude/dnbg-findings\" \"$HOME/.claude/dnbg/findings\""* ]]
}

@test "the message stays valid JSON when a path holds a backslash" {
  export HOME="$BATS_TEST_TMPDIR/ho\\me"
  mkdir -p "$HOME/.claude/dnbg-findings/acme" && touch "$HOME/.claude/dnbg-findings/acme/f.md"
  run "$HOOK"
  [[ "$(message)" == *"$HOME/.claude/dnbg-findings"* ]]
}

@test "the named move lands the entries where the session reads them" {
  mkdir -p "$HOME/.claude/dnbg-findings/acme/api" && touch "$HOME/.claude/dnbg-findings/acme/api/f.md"
  export CLAUDE_PLUGIN_OPTION_DATA_DIR='~/dnbg'
  run "$HOOK"
  eval "$(message | sed -n 's/^  //p')"
  [ -f "$HOME/dnbg/findings/acme/api/f.md" ]
  run "$HOOK"
  [ -z "$output" ]
}

@test "says nothing when a configured directory is the legacy one" {
  mkdir -p "$HOME/.claude/dnbg-findings/acme/api"
  export CLAUDE_PLUGIN_OPTION_FINDINGS_DIR='~/.claude/dnbg-findings'
  run "$HOOK"
  [ -z "$output" ]
}
