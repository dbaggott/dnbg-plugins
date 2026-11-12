#!/usr/bin/env bats
#
# Tests for the SessionStart setup nudge. Each runs a copy of the hooks and
# scripts beside its own roles/ (role-tree.bash), where the shipped reviewer
# role refuses to fall back and starts with no App. `claude` is a stub at a
# supported version, so the client on the developer's PATH decides nothing.

load role-tree

setup() {
  make_role_tree
  stub_forge
  add_role author operator
  NUDGE="$TREE/hooks/setup-nudge.sh"
  printf '#!/usr/bin/env bash\necho "2.1.311 (Claude Code)"\n' > "$STUB/claude"
  chmod +x "$STUB/claude"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  unset CLAUDE_PLUGIN_OPTION_OWNERS CLAUDE_PLUGIN_OPTION_SETUP_NOTICE CLAUDE_CODE_ENTRYPOINT NO_COLOR
}

message() { jq -er '.systemMessage' <<<"$output"; }
NOTICE='NOTICE: Run /dnbg-workflow:setup to finish configuration.'

@test "a fresh install is pointed at the setup command, in one line and with no network call" {
  run "$NUDGE"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$(message)" = "$NOTICE" ]
  # Reading the stored login is the one `gh` call, and it is local.
  ! grep -v '^gh auth token ' "$NET_LOG"
}

@test "it goes to the user alone: the output carries nothing for the model's context" {
  run "$NUDGE"
  [ "$(jq -c 'keys' <<<"$output")" = '["systemMessage"]' ]
}

@test "printed with owners set while the reviewer has no App" {
  export CLAUDE_PLUGIN_OPTION_OWNERS=acme
  run "$NUDGE"
  [ "$(message)" = "$NOTICE" ]
}

@test "printed with the reviewer configured while owners is empty" {
  export DNBG_REVIEWER_APP_ID=42
  run "$NUDGE"
  [ "$(message)" = "$NOTICE" ]
}

@test "the terminal client gets it in bold yellow, as valid JSON, unless NO_COLOR is set" {
  export CLAUDE_CODE_ENTRYPOINT=cli
  run "$NUDGE"
  [ "$(message)" = $'\033[1;33m'"$NOTICE"$'\033[0m' ]
  NO_COLOR=1 run "$NUDGE"
  [ "$(message)" = "$NOTICE" ]
  CLAUDE_CODE_ENTRYPOINT=sdk-ts run "$NUDGE"
  [ "$(message)" = "$NOTICE" ]
}

@test "silent when owners is set and the reviewer configured" {
  export CLAUDE_PLUGIN_OPTION_OWNERS=acme DNBG_REVIEWER_APP_ID=42
  run "$NUDGE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "owners of separators alone is empty, as the hooks read it" {
  export CLAUDE_PLUGIN_OPTION_OWNERS=' , ' DNBG_REVIEWER_APP_ID=42
  run "$NUDGE"
  [ "$(message)" = "$NOTICE" ]
}

@test "printed while a tool the check looks for is missing" {
  export CLAUDE_PLUGIN_OPTION_OWNERS=acme DNBG_REVIEWER_APP_ID=42
  local bin="$BATS_TEST_TMPDIR/noopenssl" b; mkdir -p "$bin"
  for b in bash env dirname grep jq git python3 curl; do ln -sf "$(command -v "$b")" "$bin/$b"; done
  ln -sf "$STUB/gh" "$bin/gh"; ln -sf "$STUB/claude" "$bin/claude"
  run env PATH="$bin" "$NUDGE"
  [ "$(message)" = "$NOTICE" ]
}

@test "silent with the notice turned off, whatever is incomplete" {
  CLAUDE_PLUGIN_OPTION_SETUP_NOTICE=false run "$NUDGE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  CLAUDE_PLUGIN_OPTION_SETUP_NOTICE=False run "$NUDGE"
  [ -z "$output" ]
}

@test "the notice is on for any value but the negative" {
  local v
  for v in true '' yes; do
    CLAUDE_PLUGIN_OPTION_SETUP_NOTICE="$v" run "$NUDGE"
    [ "$(message)" = "$NOTICE" ]
  done
}

@test "a role that falls back does not print it" {
  export CLAUDE_PLUGIN_OPTION_OWNERS=acme DNBG_REVIEWER_APP_ID=42
  run "$NUDGE"
  [ -z "$output" ]
  run "$TREE/scripts/as-role.sh" --fallbacks
  [ "$output" = "result=OK roles=author" ]
}

@test "printed on a resolver refusal, which leaves no role able to post" {
  export CLAUDE_PLUGIN_OPTION_OWNERS=acme DNBG_REVIEWER_APP_ID=42 DNBG_AUTHOR_APP_ID=42
  run "$NUDGE"
  [ "$(message)" = "$NOTICE" ]
}

@test "printed without jq, whatever owners holds" {
  local bin="$BATS_TEST_TMPDIR/nojq" b; mkdir -p "$bin"
  for b in bash dirname tr; do ln -sf "$(command -v "$b")" "$bin/$b"; done
  run env PATH="$bin" CLAUDE_PLUGIN_OPTION_OWNERS=acme "$NUDGE"
  [ "$status" -eq 0 ]
  [ "$output" = "{\"systemMessage\":\"$NOTICE\"}" ]
}

@test "silent when the check gives no result" {
  export CLAUDE_PLUGIN_OPTION_OWNERS=acme DNBG_REVIEWER_APP_ID=42
  printf '#!/usr/bin/env bash\nexit 3\n' > "$TREE/scripts/setup-check.sh"
  run "$NUDGE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the manifest runs it at startup, and never for a subagent" {
  local hooks="$ROLE_ROOT/hooks/hooks.json"
  run jq -r '.hooks.SessionStart[] | select(.hooks[].command | endswith("/hooks/setup-nudge.sh")) | .matcher' "$hooks"
  [ "$output" = startup ]
  run jq -r '[.hooks | to_entries[] | select(.key != "SessionStart") | .value[].hooks[].command
              | select(endswith("/hooks/setup-nudge.sh"))] | length' "$hooks"
  [ "$output" = 0 ]
}
