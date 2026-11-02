#!/usr/bin/env bash
# Record real sessions' transcripts as usage-sweep.sh's fixture.
#
#   capture-usage-sweep.sh <in-scope session id> <out-of-scope session id>
#
# Pick an in-scope session with a `dnbg-workflow:` Skill tool use, a
# `dnbg-workflow:` subagent, a subagent at spawn depth 2, a Read and a Bash
# command at the installed plugin, a Read of a checkout copy and a wake; and
# an out-of-scope one with none of those, on another date. Writes, under
# tests/fixtures/usage-sweep/config/, a config root the tests copy in:
#
# - `projects/-Users-someone-git-repo/<id>.jsonl` per session, and its
#   `<id>/subagents/agent-<id>.jsonl`, each entry scrubbed to `type`,
#   `timestamp`, `message.id` and `message.usage`. Of `message.content`, an
#   assistant entry keeps its `tool_use` blocks naming a plugin path, with
#   `name` and, of `input`, a Skill's `skill`, or a Read's `file_path` or a
#   Bash `command` reduced to the plugin paths it names. Each path's root is a
#   stand-in: `<config>` for one under the installed plugin, keeping the tail
#   from `plugins/cache/` on, and `<checkout>` for one with a `dnbg-workflow/`
#   component anywhere else, keeping the tail from `dnbg-workflow/` on. A
#   wake's string content becomes `<task-notification>`. Nothing else is kept,
#   so no prompt, command text, tool output or `cwd` is committed.
# - `.meta.json` beside each subagent transcript, kept to `agentType`,
#   `spawnDepth` and `parentAgentId`.
# - `plugins/cache/<marketplace>/dnbg-workflow/<version>/…`, an empty file (a
#   bare shebang for a `.sh`) for each plugin file a kept path names that the
#   real installed copy carries, a checkout path's under the first installed
#   copy carrying it, and a directory
#   for each kept path that is one there, holding a `.keep` if otherwise empty.
#
# and `captured.json` beside it, naming the Claude Code version and the date.
# It prints each transcript's figures, worked independently of the sweep, for
# tests/usage-sweep.bats to pin. Re-take it after a Claude Code upgrade, since
# the entry format is internal.
set -euo pipefail

IN=${1:?usage: capture-usage-sweep.sh <in-scope session id> <out-of-scope session id>}
OUTSIDE=${2:?usage: capture-usage-sweep.sh <in-scope session id> <out-of-scope session id>}
CONFIG=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
CONFIG=${CONFIG%/}
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/usage-sweep"
PROJECT="$OUT/config/projects/-Users-someone-git-repo"
rm -rf "$OUT"; mkdir -p "$PROJECT"

# shellcheck disable=SC2016  # $-names are jq's.
SCRUB='
  def standin:
    sub("^[\"'"'"'`(]+"; "") | sub("[\"'"'"'`;:,)|&>]+$"; "")
    | sub("^~/"; "\($home)/") | gsub("\\$\\{?HOME\\}?/"; "\($home)/")
    | . as $t | ($cfg + "/plugins/cache/") as $p | ($t | index($p)) as $i
    | if $i != null then
        ($t[$i + ($p | length):]) as $tail
        | if ($tail | split("/") | .[1]) == "dnbg-workflow"
          then "<config>/plugins/cache/\($tail)" else empty end
      elif ($t | test("://")) then empty
      else ($t | capture("(^|/)(?<r>dnbg-workflow/.+)$")) | "<checkout>/\(.r)"
      end;
  def block:
    if .name == "Skill" and (.input.skill | type) == "string"
      then {type, name, input: {skill: .input.skill}}
    elif .name == "Read"
      then [.input.file_path | strings | standin] as $p
           | if $p == [] then empty else {type, name, input: {file_path: $p[0]}} end
    elif .name == "Bash"
      then [.input.command | strings | splits("\\s+") | standin] as $p
           | if $p == [] then empty else {type, name, input: {command: ($p | join(" "))}} end
    else empty end;
  {type}
  + (if (.timestamp | type) == "string" then {timestamp} else {} end)
  + (if (.message | type) == "object" then
       (.message.content) as $c
       | {message: (
           (.message | {id, usage} | with_entries(select(.value != null)))
           + if .type == "assistant" and ($c | type) == "array" then
               [$c[] | objects | select(.type == "tool_use") | block]
               | if . == [] then {} else {content: .} end
             elif .type == "user" and ($c | type) == "string" and ($c | contains("<task-notification>"))
               then {content: "<task-notification>"}
             else {} end)}
       | if .message == {} then del(.message) else . end
     else {} end)'

scrub() { jq -c --arg cfg "$CONFIG" --arg home "$HOME" "$SCRUB" "$1"; }

VERSION=
for id in "$IN" "$OUTSIDE"; do
  shopt -s nullglob
  MATCHES=("$CONFIG"/projects/*/"$id".jsonl)
  shopt -u nullglob
  [ "${#MATCHES[@]}" -eq 1 ] || { echo "not one transcript for session $id" >&2; exit 1; }
  SRC=${MATCHES[0]}
  scrub "$SRC" > "$PROJECT/$id.jsonl"
  [ -n "$VERSION" ] || VERSION=$(jq -r 'select((.version | type) == "string") | .version' "$SRC" | tail -n 1)
  shopt -s nullglob
  for sub in "${SRC%.jsonl}"/subagents/agent-*.jsonl; do
    mkdir -p "$PROJECT/$id/subagents"
    name=$(basename "$sub" .jsonl)
    scrub "$sub" > "$PROJECT/$id/subagents/$name.jsonl"
    jq '{agentType, spawnDepth, parentAgentId}' "${sub%.jsonl}.meta.json" \
      > "$PROJECT/$id/subagents/$name.meta.json"
  done
  shopt -u nullglob
done

# The installed tree, as empty files.
INSTALLS=("$CONFIG"/plugins/cache/*/dnbg-workflow/*/)
find "$PROJECT" -name '*.jsonl' -exec jq -r '.message.content[]?.input | (.file_path, .command) | strings' {} + \
  | tr ' ' '\n' | sort -u | while IFS= read -r p; do
    case "$p" in
      "<config>/"*)
        rel=${p#<config>/}
        if [ -d "$CONFIG/$rel" ]; then mkdir -p "$OUT/config/$rel"; fi
        [ -f "$CONFIG/$rel" ] || continue
        mkdir -p "$(dirname "$OUT/config/$rel")"; : > "$OUT/config/$rel" ;;
      "<checkout>/dnbg-workflow/"*)
        rest=${p#<checkout>/dnbg-workflow/}
        for d in "${INSTALLS[@]}"; do
          [ -f "$d$rest" ] || continue
          rel=${d#"$CONFIG"/}$rest
          mkdir -p "$(dirname "$OUT/config/$rel")"; : > "$OUT/config/$rel"
          break
        done ;;
    esac
  done

# CI shellchecks every `.sh` in the tree, and an empty one fails for want of a
# shebang.
find "$OUT/config/plugins" -type f -name '*.sh' -exec sh -c 'echo "#!/usr/bin/env bash" > "$1"' _ {} \;

# git keeps no empty directory.
find "$OUT/config/plugins" -type d -empty -exec touch {}/.keep \;

jq -n --arg v "$VERSION" --arg d "$(date -u +%F)" '{claude_code: $v, date: $d}' > "$OUT/captured.json"

# Each transcript's figures, worked independently of the sweep.
find "$PROJECT" -name '*.jsonl' | sort | while IFS= read -r f; do
  jq -s -r --arg f "${f#"$PROJECT"/}" '
    ([.[] | .timestamp | strings] | min) as $ts
    | ([.[] | select(.type == "user" and .message.content == "<task-notification>")] | length) as $w
    | [.[] | select(.type == "assistant" and .message.usage != null)]
    | group_by(.message.id) | map(.[-1].message.usage)
    | "\($f) first=\($ts) requests=\(length) input=\(map(.input_tokens // 0) | add // 0) cache_write=\(map(.cache_creation_input_tokens // 0) | add // 0) cache_read=\(map(.cache_read_input_tokens // 0) | add // 0) output=\(map(.output_tokens // 0) | add // 0) wakes=\($w)"' "$f"
done
