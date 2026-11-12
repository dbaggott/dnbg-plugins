#!/usr/bin/env bats
#
# Tests for the setup state check. Each runs a copy of the scripts beside its own
# roles/ (role-tree.bash), on a PATH holding only what the test links into it, so
# a tool is absent by being left out. `gh` and `claude` are stubs.

load role-tree

setup() {
  make_role_tree
  add_role author operator
  CHECK="$TREE/scripts/setup-check.sh"
  mkdir -p "$TREE/.claude-plugin"
  echo '{"name":"dnbg-workflow"}' > "$TREE/.claude-plugin/plugin.json"

  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
  BIN="$BATS_TEST_TMPDIR/path"; mkdir -p "$BIN"
  # What the scripts themselves run, then the six tools the check looks for.
  link bash env dirname grep tr awk
  link jq git python3 openssl curl
  export GH_LOGIN="$BATS_TEST_TMPDIR/gh-login"; : > "$GH_LOGIN"
  cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2" = "auth token" ] && [ -f "$GH_LOGIN" ] && { echo gho_stub; exit 0; }
exit 1
STUB
  chmod +x "$BIN/gh"
  claude_version "2.1.311 (Claude Code)"
}

link() {  # <bin>...
  local bin
  for bin in "$@"; do ln -sf "$(command -v "$bin")" "$BIN/$bin"; done
}

claude_version() {  # <what `claude --version` prints>
  printf '#!/usr/bin/env bash\necho "%s"\n' "$1" > "$BIN/claude"
  chmod +x "$BIN/claude"
}

# Each id is recorded as installed somewhere else, except one given as
# `<id>=here`, which is recorded at the tree the check runs from.
record_installs() {  # <plugin@marketplace>[=here]...
  printf '%s\n' "$@" | jq -R --arg here "$TREE" '
      (endswith("=here")) as $h | (sub("=here$"; "")) as $id
      | {($id): [{scope: "user", installPath: (if $h then $here else "/elsewhere/" + $id end)}]}' \
    | jq -s '{version: 2, plugins: add}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
}

# Every case ends on exactly one result line, whatever else it asserts.
check() {
  run env PATH="$BIN" "$CHECK" "$@"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^result=' <<<"$output")" -eq 1 ] || { echo "$output"; false; }
  [[ "${lines[${#lines[@]}-1]}" == result=* ]] || { echo "$output"; false; }
}

has_line() { grep -qxF -- "$1" <<<"$output" || { echo "no line: $1"; echo "$output"; false; }; }

@test "a fresh install reads every check, and is open on owners and roles" {
  check --owners='${user_config.owners}' --retrospectives='${user_config.retrospectives}' \
    --version-stamp='${user_config.version_stamp}' --setup-notice='${user_config.setup_notice}'
  has_line "check=tools state=ok missing=none"
  has_line "check=gh-auth state=ok"
  has_line "check=claude-code state=ok version=2.1.311 floor=2.1.207"
  has_line "check=owners state=empty"
  has_line "check=roles state=unconfigured configured=none fallback=author unconfigured=reviewer"
  has_line "check=retrospectives state=off"
  has_line "check=version-stamp state=off"
  has_line "check=setup-notice state=on"
  has_line "check=plugins state=unknown self=none installed=none"
  has_line "check=summary-dir state=unknown"
  has_line "result=OK setup=incomplete open=owners,roles"
  [ "${#lines[@]}" -eq 11 ]
}

@test "owners set, the reviewer configured and the tools present is complete, whatever the optional settings" {
  export DNBG_REVIEWER_APP_ID=42
  check --owners='acme-corp, yourname'
  has_line "check=owners state=set value=acme-corp,yourname"
  has_line "check=roles state=ok configured=reviewer fallback=author unconfigured=none"
  has_line "result=OK setup=complete open=none"
  check --owners=acme --retrospectives=true --version-stamp=true
  has_line "result=OK setup=complete open=none"
}

@test "owners is empty as a placeholder, an empty value, an absent flag, or separators alone" {
  local arg
  for arg in '--owners=${user_config.owners}' '--owners=' '--owners= , ,' '--retrospectives=true'; do
    check "$arg"
    has_line "check=owners state=empty"
  done
}

@test "an optional setting is on for the affirmative alone" {
  check --retrospectives=true --version-stamp=TRUE
  has_line "check=retrospectives state=on"
  has_line "check=version-stamp state=on"
  local v
  for v in false yes '${user_config.retrospectives}'; do
    check --retrospectives="$v" --version-stamp="$v"
    has_line "check=retrospectives state=off"
    has_line "check=version-stamp state=off"
  done
}

@test "a missing tool is named and opens the check" {
  rm "$BIN/python3" "$BIN/curl"
  check --owners=acme
  has_line "check=tools state=missing missing=python3,curl"
  has_line "result=OK setup=incomplete open=tools,roles"
}

@test "without jq, roles and plugins are unknown rather than open" {
  rm "$BIN/jq"
  record_installs dnbg-workflow@dnbg
  check --owners=acme
  has_line "check=tools state=missing missing=jq"
  has_line "check=roles state=unknown configured=none fallback=none unconfigured=none"
  has_line "check=plugins state=unknown self=none installed=none"
  has_line "check=summary-dir state=unknown"
  has_line "result=OK setup=incomplete open=tools"
}

@test "gh with no stored login opens gh-auth, and no gh leaves it unknown" {
  rm "$GH_LOGIN"
  check --owners=acme
  has_line "check=gh-auth state=none"
  has_line "result=OK setup=incomplete open=gh-auth,roles"
  rm "$BIN/gh"
  check --owners=acme
  has_line "check=gh-auth state=unknown"
  has_line "result=OK setup=incomplete open=tools,roles"
}

@test "gh-auth reads the stored login, not a token in the environment" {
  rm "$GH_LOGIN"
  cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ] && exit 0
exit 1
STUB
  GH_TOKEN=ghs_x GITHUB_TOKEN=ghs_y check --owners=acme
  has_line "check=gh-auth state=none"
}

@test "the client version is compared with the floor field by field" {
  export DNBG_REVIEWER_APP_ID=42
  claude_version "2.1.206 (Claude Code)"
  check --owners=acme
  has_line "check=claude-code state=below version=2.1.206 floor=2.1.207"
  has_line "result=OK setup=incomplete open=claude-code"
  local v
  for v in 2.1.207 2.10.0 3.0.0; do
    claude_version "$v (Claude Code)"
    check --owners=acme
    has_line "check=claude-code state=ok version=$v floor=2.1.207"
  done
  claude_version "1.9.999"
  check --owners=acme
  has_line "check=claude-code state=below version=1.9.999 floor=2.1.207"
}

@test "a client version that cannot be read is unknown, and not open" {
  export DNBG_REVIEWER_APP_ID=42
  claude_version "Claude Code, some build"
  check --owners=acme
  has_line "check=claude-code state=unknown version=unknown floor=2.1.207"
  has_line "result=OK setup=complete open=none"
  rm "$BIN/claude"
  check --owners=acme
  has_line "check=claude-code state=unknown version=unknown floor=2.1.207"
}

@test "a resolver refusal opens roles with its reason" {
  export DNBG_REVIEWER_APP_ID=42 DNBG_AUTHOR_APP_ID=42
  check --owners=acme
  has_line "check=roles state=error configured=none fallback=none unconfigured=none reason=shared-identity"
  has_line "result=OK setup=incomplete open=roles"
}

@test "plugins names the install the check runs from, and the siblings recorded beside it" {
  record_installs other@elsewhere dnbg-workflow@old dnbg-workflow@dnbg=here \
    dnbg-agent-summaries@dnbg dnbg-practices@dnbg
  check
  has_line "check=plugins state=ok self=dnbg-workflow@dnbg installed=dnbg-practices,dnbg-agent-summaries"
  # Installed, but this copy is not that install: a --plugin-dir load.
  record_installs dnbg-workflow@dnbg
  check
  has_line "check=plugins state=ok self=none installed=none"
  record_installs other@elsewhere
  check
  has_line "check=plugins state=ok self=none installed=none"
  echo 'not json' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  check
  has_line "check=plugins state=unknown self=none installed=none"
}

@test "the setup notice is off for the negative alone" {
  check --setup-notice=FALSE
  has_line "check=setup-notice state=off"
  local v
  for v in true no '' '${user_config.setup_notice}'; do
    check --setup-notice="$v"
    has_line "check=setup-notice state=on"
  done
}

# The summaries plugin, recorded as installed from a directory holding its
# manifest, with the user's settings.json holding <summary_dir> when given.
install_summaries() {  # [<summary_dir>]
  local at="$BATS_TEST_TMPDIR/summaries"
  mkdir -p "$at/.claude-plugin"
  echo '{"userConfig":{"summary_dir":{"default":"~/.claude/dnbg-agent-summaries"}}}' \
    > "$at/.claude-plugin/plugin.json"
  jq -n --arg at "$at" \
    '{version: 2, plugins: {"dnbg-agent-summaries@dnbg": [{scope: "user", installPath: $at}]}}' \
    > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  rm -f "$CLAUDE_CONFIG_DIR/settings.json"
  [ $# -eq 0 ] || jq -n --arg d "$1" \
    '{pluginConfigs: {"dnbg-agent-summaries@dnbg": {options: {summary_dir: $d}}}}' \
    > "$CLAUDE_CONFIG_DIR/settings.json"
}

@test "summary-dir is the directory the user set, and absent without the plugin" {
  install_summaries '~/Obsidian/agent-summaries'
  check
  has_line "check=summary-dir state=ok value=~/Obsidian/agent-summaries"
  install_summaries /srv/notes
  check
  has_line "check=summary-dir state=ok value=/srv/notes"
  record_installs dnbg-practices@dnbg
  check
  has_line "check=summary-dir state=absent"
}

@test "summary-dir is the manifest's default when unset, or set to a value the skill refuses" {
  install_summaries
  check
  has_line "check=summary-dir state=ok value=~/.claude/dnbg-agent-summaries"
  local v
  for v in '' relative/path '/has space' '~other/notes' '/a;b'; do
    install_summaries "$v"
    check
    has_line "check=summary-dir state=ok value=~/.claude/dnbg-agent-summaries"
  done
}

@test "summary-dir is unknown when the installed manifest cannot be read" {
  install_summaries
  rm "$BATS_TEST_TMPDIR/summaries/.claude-plugin/plugin.json"
  check
  has_line "check=summary-dir state=unknown"
}

@test "an argument it does not know is bad-args, and nothing else is printed" {
  check --owner=acme
  [ "$output" = "result=ERROR reason=bad-args" ]
  check acme
  [ "$output" = "result=ERROR reason=bad-args" ]
}
