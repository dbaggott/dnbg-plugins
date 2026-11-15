#!/usr/bin/env bats
#
# Tests for the retrospective writer. The usage is read from the
# session-usage.bats fixture, copied under a CLAUDE_CONFIG_DIR of the test's
# own; `gh` is stubbed, recording each call and keeping each comment body it is
# handed. No role is configured, so author and orchestrator post as the
# operator and reviewer refuses.

WRITE="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/write-retrospective.sh"
REFERENCE="${BATS_TEST_DIRNAME}/../dnbg-workflow/skills/process-review/references/retrospective.md"
MANIFEST="${BATS_TEST_DIRNAME}/../dnbg-workflow/.claude-plugin/plugin.json"
FIXTURE="${BATS_TEST_DIRNAME}/fixtures/session-usage"
ID=0b6c1e1a-1111-4222-8333-444455556666
MAIN_NONCE=usage-0000000000000000
SELF_NONCE=usage-7bee05399d9d6f22
SESSION_LINE="result=OK scope=session agent=main requests=15 input=30 cache_write=63239 cache_read=284227 output=4075"
CHILD1="child=general-purpose id=a203bc81e0c8339ce depth=1 parent=session requests=7 input=14 cache_write=33068 cache_read=147064 output=1791"
CHILD2="child=general-purpose id=a7bee05399d9d6f22 depth=2 parent=a203bc81e0c8339ce requests=3 input=6 cache_write=12363 cache_read=38032 output=741"
ISSUE=https://github.com/acme/widgets/issues/48

setup() {
  local v
  for v in $(compgen -v DNBG_); do unset "$v"; done
  unset GH_TOKEN GITHUB_TOKEN
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg"; mkdir -p "$XDG_CONFIG_HOME"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  export CLAUDE_CODE_SESSION_ID="$ID"
  local project="$CLAUDE_CONFIG_DIR/projects/-Users-someone-git-repo"
  mkdir -p "$project/$ID"
  cp "$FIXTURE/main.jsonl" "$project/$ID.jsonl"
  cp -R "$FIXTURE/subagents" "$project/$ID/subagents"

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  export POSTED="$BATS_TEST_TMPDIR/posted"; mkdir -p "$POSTED"
  export GH_FAIL="$BATS_TEST_TMPDIR/gh-fail"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
case "$1" in
  api) [ "$2" = user ] && echo operator-login ;;
  issue|pr)
    [ ! -e "$GH_FAIL" ] || exit 1
    cat > "$POSTED/$(ls "$POSTED" | wc -l | tr -d ' ')"
    echo "https://github.com/acme/widgets/issues/48#issuecomment-1" ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"

  BODY="$BATS_TEST_TMPDIR/body.md"
  printf '%s\n' '## Slowed or blocked' '' '- `watch-pr.sh`: slow.' '' \
    '## Skill wrong or missing' '' 'Nothing.' '' '## Worked around' '' 'Nothing.' '' \
    '## Wished to ask' '' 'Nothing.' '' '## Read but not used' '' 'Nothing.' > "$BODY"
  ROOT="$HOME/.claude/dnbg/retrospectives"
}

path_of() {  # <result line> -> its path= value
  local p="${1#*path=}"; printf '%s' "${p%% *}"
}

frontmatter() {  # <file>
  awk 'NR == 1 { next } /^---$/ { exit } { print }' "$1"
}

@test "--begin prints a fresh nonce, then the prompt section as retrospective.md has it" {
  run "$WRITE" --begin
  [ "$status" -eq 0 ]
  [[ ${lines[0]} =~ ^usage-[0-9a-f]{16}$ ]]
  local want
  want=$(awk '/^## The prompt$/ { on = 1; print; next } on && /^## / { exit } on' "$REFERENCE")
  [ -n "$want" ]
  [ "$(printf '%s\n' "$output" | tail -n +3)" = "$want" ]
  [[ $want == *'**Slowed or blocked**'* && $want == *'`Nothing.`'* && $want == *'No secrets'* ]]
}

@test "scope=session writes the frontmatter with children and posts the Usage: comment as the role" {
  run "$WRITE" "$MAIN_NONCE" --role=orchestrator --issue="$ISSUE" --body="$BODY"
  [ "$status" -eq 0 ]
  [[ $output =~ ^result=OK\ path=$ROOT/acme/widgets/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z-48-orchestrator\.md\ usage=OK\ usage_comment=posted$ ]]
  local f; f=$(path_of "$output")
  local date; date=$(basename "$f"); date=${date:0:10}
  local version; version=$(jq -r .version "$MANIFEST")
  [ "$(frontmatter "$f")" = "$(cat <<EOF
tags:
  - retrospective
  - orchestrator
role: orchestrator
issue: $ISSUE
plugin_version: $version
date: $date
usage:
  result: OK
  scope: session
  agent: main
  requests: 15
  input: 30
  cache_write: 63239
  cache_read: 284227
  output: 4075
children:
  - agent: general-purpose
    id: a203bc81e0c8339ce
    depth: 1
    parent: session
    requests: 7
    input: 14
    cache_write: 33068
    cache_read: 147064
    output: 1791
  - agent: general-purpose
    id: a7bee05399d9d6f22
    depth: 2
    parent: a203bc81e0c8339ce
    requests: 3
    input: 6
    cache_write: 12363
    cache_read: 38032
    output: 741
EOF
)" ]
  # The body follows the closing `---` and a blank line, as given.
  [ "$(awk 'f { print } /^---$/ && NR > 1 { f = 1 }' "$f" | tail -n +2)" = "$(cat "$BODY")" ]
  grep -qx 'issue comment 48 --repo acme/widgets --body-file -' "$CALLS"
}

# Issue 44's digest recognises the comment by its first line, so the comment's
# bytes are pinned here: `Usage:`, a blank line, then the result line and each
# child line in a fenced block.
@test "the Usage: comment is exactly the pinned format" {
  run "$WRITE" "$MAIN_NONCE" --role=author --issue="$ISSUE" --body="$BODY"
  [[ $output == *" usage_comment=posted" ]]
  local want
  want=$(printf '%s\n' 'Usage:' '' '```' "$SESSION_LINE" "$CHILD1" "$CHILD2" '```')
  [ "$(cat "$POSTED/0")" = "$want" ]
  [ "$(head -1 "$POSTED/0")" = "Usage:" ]
}

@test "scope=self writes no children and posts nothing" {
  run "$WRITE" "$SELF_NONCE" --role=reviewer --issue="$ISSUE" --body="$BODY"
  [[ $output =~ ^result=OK\ path=.*-48-reviewer\.md\ usage=OK\ usage_comment=none$ ]]
  local f; f=$(path_of "$output")
  frontmatter "$f" | grep -qx '  scope: self'
  frontmatter "$f" | grep -qx '  agent: general-purpose'
  ! frontmatter "$f" | grep -q '^children:' || false
  ! grep -q '^issue\|^pr' "$CALLS" || false
}

@test "an UNKNOWN usage still writes the file, with the reason, and posts nothing" {
  run "$WRITE" usage-1111111111111111 --role=author --issue="$ISSUE" --body="$BODY"
  [[ $output =~ ^result=OK\ path=.*-48-author\.md\ usage=UNKNOWN\ usage_comment=none$ ]]
  frontmatter "$(path_of "$output")" | grep -qx 'usage: {result: UNKNOWN, reason: no-match}'
  ! grep -q '^issue\|^pr' "$CALLS" || false
}

@test "several issues give a YAML list, the first issue's directory and number" {
  run "$WRITE" "$SELF_NONCE" --role=author --issue=https://github.com/acme/widgets/issues/7 \
    --issue=https://github.com/acme/widgets/issues/12 --issue=https://github.com/beta/app/issues/3 \
    --body="$BODY"
  local f; f=$(path_of "$output")
  [[ $f == "$ROOT/acme/widgets/"*-7-author.md ]]
  frontmatter "$f" | grep -q '^issue:$'
  [ "$(frontmatter "$f" | sed -n '/^issue:$/,/^[a-z]/p' | grep '^  - ')" = "$(printf '%s\n' \
    '  - https://github.com/acme/widgets/issues/7' '  - https://github.com/acme/widgets/issues/12' \
    '  - https://github.com/beta/app/issues/3')" ]
}

@test "several issues passed out of order are ordered by repo, then number" {
  run "$WRITE" "$SELF_NONCE" --role=author --issue=https://github.com/beta/app/issues/3 \
    --issue=https://github.com/acme/widgets/issues/12 --issue=https://github.com/acme/widgets/issues/7 \
    --body="$BODY"
  local f; f=$(path_of "$output")
  [[ $f == "$ROOT/acme/widgets/"*-7-author.md ]]
  [ "$(frontmatter "$f" | grep '^  - https' | head -1)" = '  - https://github.com/acme/widgets/issues/7' ]
  [ "$(frontmatter "$f" | grep '^  - https' | tail -1)" = '  - https://github.com/beta/app/issues/3' ]
}

@test "work under no issue is keyed on its PR, and its comment goes on the PR" {
  run "$WRITE" "$MAIN_NONCE" --role=author --issue=https://github.com/acme/widgets/pull/90 --body="$BODY"
  local f; f=$(path_of "$output")
  [[ $f == "$ROOT/acme/widgets/"*-90-author.md ]]
  frontmatter "$f" | grep -qx 'issue: https://github.com/acme/widgets/pull/90'
  grep -qx 'pr comment 90 --repo acme/widgets --body-file -' "$CALLS"
}

@test "--root puts the file under that root, and expands a leading ~/" {
  run "$WRITE" "$SELF_NONCE" --role=author --issue="$ISSUE" --body="$BODY" --root="$BATS_TEST_TMPDIR/elsewhere"
  [[ $(path_of "$output") == "$BATS_TEST_TMPDIR/elsewhere/acme/widgets/"* ]]
  run "$WRITE" "$SELF_NONCE" --role=author --issue="$ISSUE" --body="$BODY" --root='~/retro'
  [[ $(path_of "$output") == "$HOME/retro/acme/widgets/"* ]]
}

@test "a relative --root is refused, with nothing written" {
  run "$WRITE" "$SELF_NONCE" --role=author --issue="$ISSUE" --body="$BODY" --root=retro
  [ "$output" = "result=ERROR reason=bad-root" ]
  [ ! -e "$ROOT" ]
  [ ! -e retro ]
}

@test "a failed post leaves the file written, and --post-usage posts it from the frontmatter" {
  touch "$GH_FAIL"
  run "$WRITE" "$MAIN_NONCE" --role=author --issue="$ISSUE" --body="$BODY"
  [[ $output == *" usage=OK usage_comment=failed" ]]
  local f; f=$(path_of "$output")
  [ -s "$f" ]
  rm "$GH_FAIL"
  run "$WRITE" --post-usage="$f"
  [ "$output" = "result=OK path=$f usage_comment=posted" ]
  [ "$(cat "$POSTED/0")" = "$(printf '%s\n' 'Usage:' '' '```' "$SESSION_LINE" "$CHILD1" "$CHILD2" '```')" ]
}

@test "--post-usage on a scope=self file posts nothing" {
  run "$WRITE" "$SELF_NONCE" --role=author --issue="$ISSUE" --body="$BODY"
  run "$WRITE" --post-usage="$(path_of "$output")"
  [[ $output == *" usage_comment=none" ]]
  ! grep -q '^issue\|^pr' "$CALLS" || false
}

@test "--post-usage on an UNKNOWN file posts nothing, and on a file it did not write refuses" {
  run "$WRITE" usage-1111111111111111 --role=author --issue="$ISSUE" --body="$BODY"
  local f; f=$(path_of "$output")
  run "$WRITE" --post-usage="$f"
  [ "$output" = "result=OK path=$f usage_comment=none" ]
  run "$WRITE" --post-usage="$BODY"
  [ "$output" = "result=ERROR reason=bad-file" ]
  ! grep -q '^issue\|^pr' "$CALLS" || false
}

@test "a reviewer posts as the reviewer role, which refuses with no App, so the post fails" {
  run "$WRITE" "$MAIN_NONCE" --role=issue-reviewer --issue="$ISSUE" --body="$BODY"
  [[ $output == *" usage=OK usage_comment=failed" ]]
  [ -s "$(path_of "$output")" ]
  ! grep -q '^issue comment' "$CALLS" || false
}

@test "a body missing a heading is refused, with nothing written" {
  grep -v '^## Wished to ask$' "$BODY" > "$BATS_TEST_TMPDIR/short.md"
  run "$WRITE" "$MAIN_NONCE" --role=author --issue="$ISSUE" --body="$BATS_TEST_TMPDIR/short.md"
  [ "$output" = "result=ERROR reason=bad-body" ]
  [ ! -e "$ROOT" ]
  [ ! -s "$CALLS" ]
}

@test "a role outside the five, or an issue that is not a GitHub URL, is refused" {
  run "$WRITE" "$MAIN_NONCE" --role=tester --issue="$ISSUE" --body="$BODY"
  [ "$output" = "result=ERROR reason=bad-args" ]
  run "$WRITE" "$MAIN_NONCE" --role=author --issue=acme/widgets#48 --body="$BODY"
  [ "$output" = "result=ERROR reason=bad-args" ]
  [ ! -e "$ROOT" ]
}
