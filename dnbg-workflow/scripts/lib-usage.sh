#!/usr/bin/env bash
# The usage one transcript was billed, for session-usage.sh and the usage sweep.
# Sourced, never executed: each `.`s this file and calls `usage_tally`.
#
#   usage_tally <transcript path>
#
# Prints exactly one line, then returns 0:
#   result=OK requests=<n> input=<n> cache_write=<n> cache_read=<n> output=<n>
#   result=UNKNOWN reason=parse
#
# It reads every entry with `type == "assistant"` that carries a
# `message.usage` object, whatever its `isSidechain`: every assistant entry in
# a subagent's own transcript is a sidechain one. One API request is logged as
# several such entries sharing a `message.id`, so `requests` is the number of
# distinct ids and each id's usage is summed once, from its last entry: an
# earlier one can carry a partial `output_tokens` (observed). `input` is `input_tokens`, `cache_write` `cache_creation_input_tokens`,
# `cache_read` `cache_read_input_tokens`, `output` `output_tokens`; an absent
# field counts 0. Callers add their own fields around the counts.
#
# `parse` is a line that is not a JSON object, a usage field that is not a
# number, an entry with usage but no string `message.id`, or an unreadable
# file: never a guessed number, since the entry format is internal to Claude
# Code (https://code.claude.com/docs/en/sessions) and changes between versions.

usage_tally() {
  local line
  line=$(jq -n -R -r '
    def count($u; $k):
      ($u[$k] // 0) | if type == "number" then . else error("parse") end;
    reduce (inputs
      | (try fromjson catch error("parse"))
      | if type != "object" then error("parse") else . end
      | select(.type == "assistant"
               and (.message | type) == "object"
               and (.message.usage | type) == "object")
      | .message) as $m
      ({};
       if ($m.id | type) != "string" then error("parse")
       else .[$m.id] = [count($m.usage; "input_tokens"),
                        count($m.usage; "cache_creation_input_tokens"),
                        count($m.usage; "cache_read_input_tokens"),
                        count($m.usage; "output_tokens")]
       end)
    | [.[]] as $last
    | def total($i): $last | map(.[$i]) | add // 0;
      "result=OK requests=\($last | length) input=\(total(0)) cache_write=\(total(1)) cache_read=\(total(2)) output=\(total(3))"
  ' 2>/dev/null < "$1") || line=
  if [[ $line =~ ^result=OK\ requests=[0-9]+\ input=[0-9]+\ cache_write=[0-9]+\ cache_read=[0-9]+\ output=[0-9]+$ ]]; then
    echo "$line"
  else
    echo "result=UNKNOWN reason=parse"
  fi
  return 0
}
