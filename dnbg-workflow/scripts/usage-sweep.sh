#!/usr/bin/env bash
# The usage of the plugin's agents over a date range, read from the local
# transcripts, as a report process-review can cite.
#
#   usage-sweep.sh --since=<YYYY-MM-DD> [--until=<YYYY-MM-DD>] [--root=<dir>]
#
# Prints one line, then exits 0:
#   result=OK report=<root>/_usage/<YYYY-MM-DD>T<HHMMSS>Z.md
#   result=UNKNOWN reason=bad-args|no-config-dir|no-transcripts|parse|write
#
# It reads every main transcript, `<config>/projects/*/*.jsonl`, and every
# subagent transcript, `<config>/projects/*/*/subagents/agent-*.jsonl` with its
# `.meta.json`, `<config>` being ${CLAUDE_CONFIG_DIR:-$HOME/.claude}. `--until`
# defaults to today (UTC) and `--root` to ~/.claude/dnbg/retrospectives; the
# report is written there with a `.json` twin of the same name.
#
# - Range. A transcript is in the range when the earliest `timestamp` among
#   its entries that carry one falls on a date from `--since` to `--until`
#   inclusive. Many entry types carry none, and a main transcript often opens
#   with one of those; a transcript with no timestamped entry is in no range,
#   counted under the frontmatter's `untimed`.
# - Scope. A main transcript is in scope when an assistant entry has a `Skill`
#   tool use whose `input.skill` starts `dnbg-workflow:`, or a tool use naming
#   a path under the installed plugin (below); a subagent transcript when its
#   meta `agentType` starts `dnbg-workflow:` or its session's main transcript
#   is in scope, whether or not that one is in the range. Whether a file
#   mentions `dnbg-workflow` decides nothing: the always-on hook text puts it
#   in every session.
# - Figures, per transcript in scope and in range: `requests` and the four
#   counts are lib-usage.sh's, so a row equals the session's `Usage:` record;
#   `wakes` the `user` entries whose string `message.content` carries
#   `<task-notification>`. `agent` is `main` or the meta `agentType`, `depth`
#   its `spawnDepth` (0 for main), `parent` its `parentAgentId`, or `session`
#   where the meta file names none, as at depth 1, or null for main.
# - Plugin-file reads, in the transcripts in scope and in range. The paths a
#   tool use names are a `Read`'s `input.file_path` and each whitespace-split
#   token of a `Bash` `input.command`, with surrounding quotes and trailing
#   punctuation trimmed and a leading `~/` or `$HOME/` expanded. One under
#   `<config>/plugins/cache/<marketplace>/dnbg-workflow/<version>/` is a read
#   of its remainder below `<version>/`, `..` resolved, counted in `files`
#   unless an installed copy has a directory there (a `cd` or an `ls`).
#   One with a `dnbg-workflow/` component anywhere else, such as a checkout,
#   whose remainder is a file in an installed copy counts under `ignored_reads`
#   and nowhere else. A path named twice in one tool use is one read.
#
# The JSON twin's keys are `range` (`since`, `until`), `ignored_reads` (a
# count), `agents` (agent -> `transcripts`, `requests`, `input`, `cache_write`,
# `cache_read`, `output`, `wakes`), `files` (plugin-relative path -> reads,
# descending) and `sessions` (one object per transcript: `session_id`,
# `agent_id` or null, `agent`, `parent`, `depth`, the counts, `wakes`). An
# agent's `transcripts` is its number of rows in `sessions`: one per main
# session or subagent dispatch, so three dispatches in one session are three.
# Every list is sorted, so a fixed input and range give byte-identical twins.
# The Markdown report carries `range`, `transcripts_read` (the count read,
# before range and scope) and `untimed` as frontmatter, then the same three
# tables.
#
# `bad-args` is a missing `--since`, a date not of the form or not on the
# calendar, `--since` after `--until`, or an unknown argument; `no-config-dir`
# a `<config>` that is not a directory; `no-transcripts` no transcript under
# it at all; `parse` a transcript line that is not a JSON object or that
# lib-usage.sh cannot count, or a meta file that is not JSON or lacks a string
# `agentType` or an integer `spawnDepth`; `write` a report or twin that could
# not be written under `<root>/_usage/`. The entry format is internal to
# Claude Code (https://code.claude.com/docs/en/sessions), so every failure is
# UNKNOWN, never a partial report.
set -euo pipefail

# shellcheck source=./lib-usage.sh
. "$(dirname "$0")/lib-usage.sh"

# The result line goes to fd 3, the script's stdout, since a failure can be
# found inside a loop whose stdout is a records file.
exec 3>&1
unknown() { echo "result=UNKNOWN reason=$1" >&3; exit 0; }

DATE_RE='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'
SINCE="" UNTIL=$(date -u +%F) ROOT="$HOME/.claude/dnbg/retrospectives"
for a in "$@"; do
  case "$a" in
    --since=*) SINCE=${a#--since=} ;;
    --until=*) UNTIL=${a#--until=} ;;
    --root=?*) ROOT=${a#--root=} ;;
    *) unknown bad-args ;;
  esac
done
[[ $SINCE =~ $DATE_RE && $UNTIL =~ $DATE_RE ]] || unknown bad-args
# A date the calendar lacks, such as 02-31, reads back as another day.
for d in "$SINCE" "$UNTIL"; do
  [ "$(jq -nr --arg d "$d" '"\($d)T00:00:00Z" | fromdateiso8601 | todate[0:10]')" = "$d" ] \
    || unknown bad-args
done
[[ ! $SINCE > $UNTIL ]] || unknown bad-args

CONFIG=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
CONFIG=${CONFIG%/}
[ -d "$CONFIG" ] || unknown no-config-dir

shopt -s nullglob
MAINS=("$CONFIG"/projects/*/*.jsonl)
SUBS=("$CONFIG"/projects/*/*/subagents/agent-*.jsonl)
INSTALLS=("$CONFIG"/plugins/cache/*/dnbg-workflow/*/)
shopt -u nullglob
[ $(( ${#MAINS[@]} + ${#SUBS[@]} )) -gt 0 ] || unknown no-transcripts

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# One transcript's timestamp, scope signal, named plugin paths and wakes.
# shellcheck disable=SC2016  # $-names are jq's.
EXTRACT='
  def norm:
    reduce (split("/")[]) as $c ([];
      if $c == "" or $c == "." then .
      elif $c == ".." then .[:-1]
      else . + [$c] end) | join("/");
  def classify:
    sub("^[\"'"'"'`(]+"; "") | sub("[\"'"'"'`;:,)|&>]+$"; "")
    | sub("^~/"; "\($home)/") | gsub("\\$\\{?HOME\\}?/"; "\($home)/")
    | . as $t | ($cfg + "/plugins/cache/") as $p | ($t | index($p)) as $i
    | if $i != null then
        ($t[$i + ($p | length):] | split("/")) as $s
        | if ($s | length) >= 4 and $s[1] == "dnbg-workflow"
          then {installed: ($s[3:] | join("/") | norm)} else empty end
      elif ($t | test("://")) then empty
      else ($t | capture("(^|/)dnbg-workflow/(?<r>.+)$")) | {checkout: (.r | norm)}
      end
    | select((.installed // .checkout) != "");
  def paths($b):
    if $b.name == "Read" then [$b.input | objects | .file_path | strings]
    elif $b.name == "Bash" then [$b.input | objects | .command | strings | splits("\\s+")]
    else [] end;
  def named($b): [paths($b)[] | select(contains("dnbg-workflow/")) | classify] | unique;
  reduce (inputs
    | (try fromjson catch error("parse"))
    | if type != "object" then error("parse") else . end) as $e
    ({ts: null, skill: false, installed: [], checkout: [], wakes: 0};
     (if ($e.timestamp | type) == "string" and (.ts == null or $e.timestamp < .ts)
      then .ts = $e.timestamp else . end)
     | ($e.message | if type == "object" then .content else null end) as $c
     | if $e.type == "user" and ($c | type) == "string" and ($c | contains("<task-notification>"))
       then .wakes += 1
       elif $e.type == "assistant" and ($c | type) == "array" then
         reduce ($c[] | objects | select(.type == "tool_use")) as $b (.;
           (if $b.name == "Skill"
               and ($b.input | objects | .skill | strings | startswith("dnbg-workflow:"))
            then .skill = true else . end)
           | named($b) as $r
           | .installed += [$r[] | .installed // empty]
           | .checkout += [$r[] | .checkout // empty])
       else . end)'

# shellcheck disable=SC2016
META='if type == "object" and (.agentType | type) == "string"
        and (.spawnDepth | type) == "number" and .spawnDepth == (.spawnDepth | floor)
      then {agent: .agentType, depth: .spawnDepth,
            parent: (.parentAgentId // "session")}
      else error("parse") end'

record() {  # <transcript> <session key> <session id> <agent id|""> <meta JSON> >> records
  local x tally
  x=$(jq -n -R -c --arg cfg "$CONFIG" --arg home "$HOME" "$EXTRACT" < "$1" 2>/dev/null) \
    || unknown parse
  tally=$(usage_tally "$1")
  [[ $tally == "result=OK "* ]] || unknown parse
  # shellcheck disable=SC2086  # The tally's fields are k=v words.
  jq -n -c --argjson x "$x" --argjson m "$5" --arg key "$2" --arg sid "$3" --arg aid "$4" \
    --args '$x + $m + {key: $key, session_id: $sid, agent_id: (if $aid == "" then null else $aid end)}
            + ($ARGS.positional | map(split("=") | {(.[0]): (.[1] | tonumber)}) | add)' \
    ${tally#result=OK }
}

for f in ${MAINS[@]+"${MAINS[@]}"}; do
  record "$f" "${f%.jsonl}" "$(basename "$f" .jsonl)" "" \
    '{"main": true, "agent": "main", "depth": 0, "parent": null}'
done >> "$WORK/records.jsonl"
for f in ${SUBS[@]+"${SUBS[@]}"}; do
  dir=${f%/subagents/*}
  name=$(basename "$f" .jsonl)
  meta=$(jq -c "$META + {main: false}" "${f%.jsonl}.meta.json" 2>/dev/null) || unknown parse
  record "$f" "$dir" "$(basename "$dir")" "${name#agent-}" "$meta"
done >> "$WORK/records.jsonl"

# Which checkout remainders name a file some installed copy carries, and which
# installed remainders name a directory there rather than a file.
in_installs() {  # <test flag> < remainders > those passing it in some copy
  local rest d
  while IFS= read -r rest; do
    for d in ${INSTALLS[@]+"${INSTALLS[@]}"}; do
      if test "$1" "$d$rest"; then printf '%s\n' "$rest"; break; fi
    done
  done
}
jq -r '.checkout[]' "$WORK/records.jsonl" | sort -u | in_installs -f > "$WORK/existing"
jq -r '.installed[]' "$WORK/records.jsonl" | sort -u | in_installs -d > "$WORK/dirs"

# shellcheck disable=SC2016
jq -s --arg since "$SINCE" --arg until "$UNTIL" \
  --slurpfile existing <(jq -R . "$WORK/existing") \
  --slurpfile dirs <(jq -R . "$WORK/dirs") '
  . as $all
  | ($existing | map({(.): true}) | add // {}) as $ok
  | ($dirs | map({(.): true}) | add // {}) as $dir
  | ([$all[] | select(.main and (.skill or (.installed | length) > 0)) | .key]
     | map({(.): true}) | add // {}) as $scoped
  | [$all[]
     | select(.ts != null and .ts[0:10] >= $since and .ts[0:10] <= $until)
     | select(if .main then $scoped[.key]
              else (.agent | startswith("dnbg-workflow:")) or $scoped[.key] end)] as $rows
  | def counts: {requests, input, cache_write, cache_read, output, wakes};
    {
      meta: {transcripts_read: ($all | length), untimed: ([$all[] | select(.ts == null)] | length)},
      twin: {
        range: {since: $since, until: $until},
        ignored_reads: ([$rows[].checkout[] | select($ok[.])] | length),
        agents: ($rows | group_by(.agent)
                 | map({(.[0].agent): ({transcripts: length} + (map(counts)
                     | {requests: (map(.requests) | add), input: (map(.input) | add),
                        cache_write: (map(.cache_write) | add), cache_read: (map(.cache_read) | add),
                        output: (map(.output) | add), wakes: (map(.wakes) | add)}))})
                 | add // {}),
        files: ([$rows[].installed[] | select($dir[.] | not)] | group_by(.) | map({path: .[0], n: length})
                 | sort_by(-.n, .path) | map({(.path): .n}) | add // {}),
        sessions: ($rows | sort_by(.session_id, .depth, (.agent_id // ""))
                   | map({session_id, agent_id, agent, parent, depth} + counts))
      }
    }' "$WORK/records.jsonl" > "$WORK/out.json" || unknown parse

STAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
OUT="$ROOT/_usage/$STAMP"
jq '.twin' "$WORK/out.json" > "$WORK/twin.json" || unknown write
# shellcheck disable=SC2016
jq -r '
  def row: map(tostring) | "| " + join(" | ") + " |";
  def dash: if . == null then "—" else . end;
  .meta as $m | .twin as $t
  | "---",
    "range: {since: \($t.range.since), until: \($t.range.until)}",
    "transcripts_read: \($m.transcripts_read)",
    "untimed: \($m.untimed)",
    "---",
    "",
    "# Usage sweep, \($t.range.since) to \($t.range.until)",
    "",
    "## Per agent",
    "",
    "| agent | transcripts | requests | input | cache_write | cache_read | output | wakes |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ($t.agents | to_entries[]
     | [.key, .value.transcripts, .value.requests, .value.input, .value.cache_write,
        .value.cache_read, .value.output, .value.wakes] | row),
    "",
    "## Per plugin file",
    "",
    "| file | reads |",
    "| --- | ---: |",
    ($t.files | to_entries[] | [.key, .value] | row),
    "",
    "## Per transcript",
    "",
    "| session | agent id | agent | parent | depth | requests | input | cache_write | cache_read | output | wakes |",
    "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ($t.sessions[]
     | [.session_id, (.agent_id | dash), .agent, (.parent | dash), .depth, .requests,
        .input, .cache_write, .cache_read, .output, .wakes] | row)
' "$WORK/out.json" > "$WORK/report.md" || unknown write
# The twin lands only with its report.
{ mkdir -p "$ROOT/_usage" && mv "$WORK/twin.json" "$OUT.json"; } 2>/dev/null || unknown write
mv "$WORK/report.md" "$OUT.md" 2>/dev/null || { rm -f "$OUT.json"; unknown write; }
echo "result=OK report=$OUT.md"
