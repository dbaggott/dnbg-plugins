#!/usr/bin/env bats
#
# Tests for the SessionStart setup nudge. Each runs a copy of the hooks and
# scripts beside its own roles/ (role-tree.bash), where the shipped reviewer
# role refuses to fall back and starts with no App.

load role-tree

setup() {
  make_role_tree
  stub_forge
  add_role author operator
  NUDGE="$TREE/hooks/setup-nudge.sh"
  unset CLAUDE_PLUGIN_OPTION_OWNERS
}

message() { jq -er '.systemMessage' <<<"$output"; }

@test "a fresh install is told about owners and the reviewer, and the command" {
  run "$NUDGE"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  local msg; msg=$(message)
  [[ "$msg" == *'`owners` is not set'* ]]
  [[ "$msg" == *"no GitHub App is set up for the reviewer role"* ]]
  [[ "$msg" == *"/dnbg-workflow:setup"* ]]
  [ ! -s "$NET_LOG" ]
}

@test "it goes to the user alone: the output carries nothing for the model's context" {
  run "$NUDGE"
  [ "$(jq -c 'keys' <<<"$output")" = '["systemMessage"]' ]
}

@test "with owners set, only the role is named" {
  export CLAUDE_PLUGIN_OPTION_OWNERS=acme
  run "$NUDGE"
  local msg; msg=$(message)
  [[ "$msg" != *owners* ]]
  [[ "$msg" == *"the reviewer role"* ]]
}

@test "with the reviewer configured, only owners is named" {
  export DNBG_REVIEWER_APP_ID=42
  run "$NUDGE"
  local msg; msg=$(message)
  [[ "$msg" == *'`owners` is not set'* ]]
  [[ "$msg" != *"GitHub App"* ]]
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
  [[ "$(message)" == *'`owners` is not set'* ]]
}

@test "silent once the marker exists" {
  mkdir -p "$XDG_CONFIG_HOME/dnbg"; : > "$XDG_CONFIG_HOME/dnbg/setup-acknowledged"
  run "$NUDGE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a role that falls back is not named" {
  run "$NUDGE"
  [[ "$(message)" != *author* ]]
}

@test "a resolver refusal leaves the roles to the fallback notice" {
  export CLAUDE_PLUGIN_OPTION_OWNERS=acme DNBG_REVIEWER_APP_ID=42 DNBG_AUTHOR_APP_ID=42
  run "$NUDGE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "without jq it still names owners, and says nothing of roles" {
  local bin="$BATS_TEST_TMPDIR/nojq" b; mkdir -p "$bin"
  for b in bash dirname tr; do ln -sf "$(command -v "$b")" "$bin/$b"; done
  run env PATH="$bin" "$NUDGE"
  [ "$status" -eq 0 ]
  local msg; msg=$(message)
  [[ "$msg" == *'`owners` is not set'* ]]
  [[ "$msg" != *"GitHub App"* ]]
}

@test "the manifest runs it at startup, and never for a subagent" {
  local hooks="$ROLE_ROOT/hooks/hooks.json"
  run jq -r '.hooks.SessionStart[] | select(.hooks[].command | endswith("/hooks/setup-nudge.sh")) | .matcher' "$hooks"
  [ "$output" = startup ]
  run jq -r '[.hooks | to_entries[] | select(.key != "SessionStart") | .value[].hooks[].command
              | select(endswith("/hooks/setup-nudge.sh"))] | length' "$hooks"
  [ "$output" = 0 ]
}
