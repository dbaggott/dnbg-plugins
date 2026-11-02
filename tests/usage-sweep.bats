#!/usr/bin/env bats
#
# Tests for the sweep of the plugin's usage over a date range. The config root
# is the fixture tests/fixtures/capture-usage-sweep.sh took from two real
# sessions, copied under a CLAUDE_CONFIG_DIR of the test's own with its
# `<config>` stand-in replaced by that directory and `<checkout>` by a checkout
# directory holding copies of the plugin files, so the installed path is
# recognised by the rule the sweep uses in production.

SWEEP="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/usage-sweep.sh"
FIXTURE="${BATS_TEST_DIRNAME}/fixtures/usage-sweep"
DAY=2026-11-01
IN=b6b92977-1150-4d9a-964e-322aa75c4e15
OUTSIDE=62794953-17f7-4340-8df4-801098876df4
# Each in-scope transcript's figures, as the capture printed them.
MAIN_ROW='{"session_id":"'$IN'","agent_id":null,"agent":"main","parent":null,"depth":0,"requests":37,"input":178,"cache_write":257723,"cache_read":3952883,"output":12060,"wakes":6}'
AUTHOR_1=a8a9b08294f032f2b
AUTHOR_1_ROW='{"session_id":"'$IN'","agent_id":"'$AUTHOR_1'","agent":"dnbg-workflow:author-orchestrated","parent":"session","depth":1,"requests":38,"input":78,"cache_write":123788,"cache_read":3250381,"output":42051,"wakes":0}'
AUTHOR_2=ab6655650f866836c
AUTHOR_2_ROW='{"session_id":"'$IN'","agent_id":"'$AUTHOR_2'","agent":"dnbg-workflow:author-orchestrated","parent":"session","depth":1,"requests":107,"input":228,"cache_write":370028,"cache_read":14054259,"output":61971,"wakes":3}'
REVIEWER=af6ebc15161c48e67
REVIEWER_ROW='{"session_id":"'$IN'","agent_id":"'$REVIEWER'","agent":"dnbg-workflow:reviewer-orchestrated","parent":"session","depth":1,"requests":17,"input":36,"cache_write":95882,"cache_read":1157066,"output":11392,"wakes":0}'
DEPTH2=ad5c431afeb8c7de5
DEPTH2_ROW='{"session_id":"'$IN'","agent_id":"'$DEPTH2'","agent":"general-purpose","parent":"'$AUTHOR_2'","depth":2,"requests":11,"input":22,"cache_write":49489,"cache_read":438649,"output":7415,"wakes":0}'
# Tool uses naming a checkout path whose file an installed copy carries,
# counted from the fixture by hand.
IGNORED=21

setup() {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  CHECKOUT="$BATS_TEST_TMPDIR/checkout"
  ROOT="$BATS_TEST_TMPDIR/root"
  cp -R "$FIXTURE/config" "$CLAUDE_CONFIG_DIR"
  mkdir -p "$CHECKOUT/dnbg-workflow"
  for v in "$CLAUDE_CONFIG_DIR"/plugins/cache/*/dnbg-workflow/*/; do
    cp -R "$v". "$CHECKOUT/dnbg-workflow/"
  done
  find "$CLAUDE_CONFIG_DIR/projects" -name '*.jsonl' -exec \
    sed -i.bak -e "s|<config>|$CLAUDE_CONFIG_DIR|g" -e "s|<checkout>|$CHECKOUT|g" {} +
  find "$CLAUDE_CONFIG_DIR/projects" -name '*.bak' -delete
  PROJECT="$CLAUDE_CONFIG_DIR/projects/-Users-someone-git-repo"
  MAIN="$PROJECT/$IN.jsonl"
}

sweep() {  # runs the sweep over DAY into ROOT; sets REPORT and TWIN
  run "$SWEEP" --since="$DAY" --until="$DAY" --root="$ROOT"
  [ "$status" -eq 0 ]
  [[ $output =~ ^result=OK\ report=$ROOT/_usage/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z\.md$ ]]
  REPORT=${output#result=OK report=}
  TWIN=${REPORT%.md}.json
}

rows() { jq -c '.sessions[]' "$TWIN"; }

@test "the report and its JSON twin are written under _usage/" {
  sweep
  [ -s "$REPORT" ]
  [ -s "$TWIN" ]
}

@test "the twin has exactly R9's top-level and per-object keys" {
  sweep
  [ "$(jq -c 'keys_unsorted' "$TWIN")" = '["range","ignored_reads","agents","files","sessions"]' ]
  [ "$(jq -c '.range | keys_unsorted' "$TWIN")" = '["since","until"]' ]
  [ "$(jq -c '[.agents[] | keys_unsorted] | unique' "$TWIN")" = \
    '[["transcripts","requests","input","cache_write","cache_read","output","wakes"]]' ]
  [ "$(jq -c '[.sessions[] | keys_unsorted] | unique' "$TWIN")" = \
    '[["session_id","agent_id","agent","parent","depth","requests","input","cache_write","cache_read","output","wakes"]]' ]
  [ "$(jq -c '[.files[] | type] | unique' "$TWIN")" = '["number"]' ]
  [ "$(jq -r '.ignored_reads | type' "$TWIN")" = number ]
}

@test "each in-scope transcript's row carries its pinned figures, sorted by session, depth and id" {
  sweep
  [ "$(rows)" = "$(printf '%s\n' "$MAIN_ROW" "$AUTHOR_1_ROW" "$AUTHOR_2_ROW" "$REVIEWER_ROW" "$DEPTH2_ROW")" ]
}

@test "the per-agent figures total the agent's rows" {
  sweep
  [ "$(jq -c '.agents["dnbg-workflow:author-orchestrated"]' "$TWIN")" = \
    '{"transcripts":2,"requests":145,"input":306,"cache_write":493816,"cache_read":17304640,"output":104022,"wakes":3}' ]
  [ "$(jq -c '.agents | keys' "$TWIN")" = \
    '["dnbg-workflow:author-orchestrated","dnbg-workflow:reviewer-orchestrated","general-purpose","main"]' ]
  [ "$(jq -c '.agents | map_values(.transcripts)' "$TWIN")" = \
    "$(jq -c '.sessions | group_by(.agent) | map({(.[0].agent): length}) | add' "$TWIN")" ]
}

@test "the out-of-scope session is in no table" {
  sweep
  run grep -qF "$OUTSIDE" "$TWIN" "$REPORT"
  [ "$status" -eq 1 ]
}

@test "a main transcript is in scope by its dnbg-workflow Skill tool use alone" {
  # Drop every tool use but the Skill one: no plugin path is named.
  jq -c 'if (.message.content | type) == "array"
         then .message.content |= map(select(.name == "Skill")) else . end' "$MAIN" > "$MAIN.new"
  mv "$MAIN.new" "$MAIN"
  grep -qF '"skill":"dnbg-workflow:orchestrate"' "$MAIN"
  sweep
  rows | grep -qF "$MAIN_ROW"
}

@test "a main transcript is in scope by a read at the installed path alone" {
  jq -c 'if (.message.content | type) == "array"
         then .message.content |= map(select(.name != "Skill")) else . end' "$MAIN" > "$MAIN.new"
  mv "$MAIN.new" "$MAIN"
  run grep -qF '"name":"Skill"' "$MAIN"
  [ "$status" -eq 1 ]
  sweep
  rows | grep -qF "$MAIN_ROW"
}

@test "with its main out of scope, a dnbg-workflow agent stays in by its agentType and a general-purpose one drops" {
  jq -c 'del(.message.content)' "$MAIN" > "$MAIN.new"
  mv "$MAIN.new" "$MAIN"
  sweep
  [ "$(rows | jq -r .agent_id)" = "$(printf '%s\n' "$AUTHOR_1" "$AUTHOR_2" "$REVIEWER")" ]
}

@test "a general-purpose agent is in scope by its session's main transcript" {
  sweep
  rows | grep -qF "$DEPTH2_ROW"
}

@test "files are keyed plugin-relative, and a directory named is not a file read" {
  sweep
  [ "$(jq '.files["scripts/as-role.sh"]' "$TWIN")" -eq 8 ]
  [ "$(jq '.files["skills/git-workflow/references/review-rounds.md"]' "$TWIN")" -eq 2 ]
  [ "$(jq '[.files | keys[] | select(startswith("/") or contains("dnbg-workflow"))] | length' "$TWIN")" -eq 0 ]
  [ -d "$CLAUDE_CONFIG_DIR/plugins/cache/dnbg/dnbg-workflow/2026.11.12/skills/orchestrate" ]
  [ "$(jq '.files | has("skills/orchestrate")' "$TWIN")" = false ]
}

@test "a read of a checkout copy counts under ignored_reads and not in files" {
  grep -qF "\"file_path\":\"$CHECKOUT/dnbg-workflow/skills/process-review/SKILL.md\"" \
    "$PROJECT/$IN/subagents/agent-$AUTHOR_1.jsonl"
  sweep
  [ "$(jq .ignored_reads "$TWIN")" -eq "$IGNORED" ]
  [ "$(jq '.files | has("skills/process-review/SKILL.md")' "$TWIN")" = false ]
}

@test "a checkout path whose file no installed copy carries is not counted" {
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-01T23:59:00.000Z","message":{"id":"msg_x","usage":{},"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/elsewhere/dnbg-workflow/scripts/no-such.sh"}}]}}' >> "$MAIN"
  sweep
  [ "$(jq .ignored_reads "$TWIN")" -eq "$IGNORED" ]
}

@test "the same path twice in one Bash command is one read" {
  local p="$CLAUDE_CONFIG_DIR/plugins/cache/dnbg/dnbg-workflow/2026.11.12/scripts/as-role.sh"
  printf '{"type":"assistant","timestamp":"2026-11-01T23:59:00.000Z","message":{"id":"msg_x","usage":{},"content":[{"type":"tool_use","name":"Bash","input":{"command":"%s \\"%s\\""}}]}}\n' "$p" "$p" >> "$MAIN"
  sweep
  [ "$(jq '.files["scripts/as-role.sh"]' "$TWIN")" -eq 9 ]
}

@test "a ~/ path under a config root at HOME/.claude counts as installed" {
  export HOME="$BATS_TEST_TMPDIR"
  printf '%s\n' '{"type":"assistant","timestamp":"2026-11-01T23:59:00.000Z","message":{"id":"msg_x","usage":{},"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat ~/config/plugins/cache/dnbg/dnbg-workflow/2026.11.12/skills/../scripts/as-role.sh"}}]}}' >> "$MAIN"
  sweep
  [ "$(jq '.files["scripts/as-role.sh"]' "$TWIN")" -eq 9 ]
}

@test "wakes count user entries only" {
  printf '%s\n' '{"type":"queue-operation","timestamp":"2026-11-01T23:59:00.000Z","content":"<task-notification>"}' \
    '{"type":"attachment","timestamp":"2026-11-01T23:59:00.000Z","message":{"content":"<task-notification>"}}' >> "$MAIN"
  sweep
  [ "$(rows | head -n 1 | jq .wakes)" -eq 6 ]
  printf '%s\n' '{"type":"user","timestamp":"2026-11-01T23:59:00.000Z","message":{"content":"x <task-notification> y"}}' >> "$MAIN"
  sweep
  [ "$(rows | head -n 1 | jq .wakes)" -eq 7 ]
}

@test "a transcript opening without a timestamp is placed by its earliest timestamped entry" {
  [ "$(head -n 1 "$MAIN" | jq 'has("timestamp")')" = false ]
  sweep
  rows | grep -qF "$MAIN_ROW"
  # An entry earlier than the rest, though logged last, moves the main a day back.
  printf '%s\n' '{"type":"user","timestamp":"2026-10-31T23:59:59.000Z","message":{"content":"x"}}' >> "$MAIN"
  sweep
  [ -z "$(rows | jq -r 'select(.agent == "main")')" ]
  run "$SWEEP" --since=2026-10-31 --until=2026-10-31 --root="$ROOT"
  TWIN=${output#result=OK report=}; TWIN=${TWIN%.md}.json
  [ "$(rows | jq -r .agent)" = main ]
}

@test "a transcript with no timestamped entry is counted untimed and in no table" {
  printf '%s\n' '{"type":"ai-title"}' '{"type":"mode"}' > "$PROJECT/untimed.jsonl"
  sweep
  grep -qx 'transcripts_read: 7' "$REPORT"
  grep -qx 'untimed: 1' "$REPORT"
  run grep -qF untimed "$TWIN"
  [ "$status" -eq 1 ]
}

@test "the range is inclusive at both ends" {
  run "$SWEEP" --since="$DAY" --until="$DAY" --root="$ROOT"
  TWIN=${output#result=OK report=}; TWIN=${TWIN%.md}.json
  [ "$(jq '.sessions | length' "$TWIN")" -eq 5 ]
  rm -rf "$ROOT"
  run "$SWEEP" --since=2026-10-30 --until=2026-10-31 --root="$ROOT"
  TWIN=${output#result=OK report=}; TWIN=${TWIN%.md}.json
  [ "$(jq '.sessions | length' "$TWIN")" -eq 0 ]
  rm -rf "$ROOT"
  run "$SWEEP" --since=2026-11-02 --until=2026-11-03 --root="$ROOT"
  TWIN=${output#result=OK report=}; TWIN=${TWIN%.md}.json
  [ "$(jq -c '[.sessions, .agents, .files]' "$TWIN")" = '[[],{},{}]' ]
}

@test "the report's frontmatter and tables carry the twin's figures" {
  sweep
  [ "$(sed -n 1,5p "$REPORT")" = "$(printf '%s\n' --- "range: {since: $DAY, until: $DAY}" 'transcripts_read: 6' 'untimed: 0' ---)" ]
  grep -qxF '| agent | transcripts | requests | input | cache_write | cache_read | output | wakes |' "$REPORT"
  grep -qxF '| main | 1 | 37 | 178 | 257723 | 3952883 | 12060 | 6 |' "$REPORT"
  grep -qxF '| scripts/as-role.sh | 8 |' "$REPORT"
  grep -qxF "| $IN | $DEPTH2 | general-purpose | $AUTHOR_2 | 2 | 11 | 22 | 49489 | 438649 | 7415 | 0 |" "$REPORT"
  grep -qxF "| $IN | — | main | — | 0 | 37 | 178 | 257723 | 3952883 | 12060 | 6 |" "$REPORT"
}

@test "two runs over the fixture write byte-identical twins" {
  sweep
  cp "$TWIN" "$BATS_TEST_TMPDIR/first.json"
  rm -rf "$ROOT"
  sleep 1
  sweep
  cmp "$BATS_TEST_TMPDIR/first.json" "$TWIN"
}

@test "an empty config root has no transcripts" {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  run "$SWEEP" --since="$DAY" --root="$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=no-transcripts" ]
  [ ! -e "$ROOT" ]
}

@test "a config root that is not a directory is unknown" {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/missing"
  run "$SWEEP" --since="$DAY" --root="$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=no-config-dir" ]
}

@test "bad arguments are unknown" {
  local args
  for args in "" "--since=2026-11-1" "--since=2026-13-01" "--since=2026-02-31" "--since=$DAY --until=2026-10-31" \
              "--since=$DAY --bogus" "--since=$DAY --root="; do
    # shellcheck disable=SC2086  # Each case is its words.
    run "$SWEEP" $args
    [ "$status" -eq 0 ]
    [ "$output" = "result=UNKNOWN reason=bad-args" ]
  done
}

@test "until defaults to today" {
  run "$SWEEP" --since="$DAY" --root="$ROOT"
  [ "$status" -eq 0 ]
  TWIN=${output#result=OK report=}; TWIN=${TWIN%.md}.json
  [ "$(jq -r .range.until "$TWIN")" = "$(date -u +%F)" ]
}

@test "a root that cannot be written is unknown, with no twin left behind" {
  : > "$BATS_TEST_TMPDIR/file"
  run "$SWEEP" --since="$DAY" --root="$BATS_TEST_TMPDIR/file"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=write" ]
  mkdir -p "$ROOT/_usage"
  chmod 555 "$ROOT/_usage"
  run "$SWEEP" --since="$DAY" --root="$ROOT"
  chmod 755 "$ROOT/_usage"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=write" ]
  [ -z "$(ls "$ROOT/_usage")" ]
}

@test "a transcript line that is not JSON is a parse failure, not a report" {
  echo 'not json' >> "$PROJECT/$IN/subagents/agent-$REVIEWER.jsonl"
  run "$SWEEP" --since="$DAY" --root="$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "result=UNKNOWN reason=parse" ]
  [ ! -e "$ROOT/_usage" ] || [ -z "$(ls "$ROOT/_usage")" ]
}

@test "a meta file without an integer spawnDepth is a parse failure" {
  echo '{"agentType":"x","spawnDepth":"1"}' > "$PROJECT/$IN/subagents/agent-$REVIEWER.meta.json"
  run "$SWEEP" --since="$DAY" --root="$ROOT"
  [ "$output" = "result=UNKNOWN reason=parse" ]
}
