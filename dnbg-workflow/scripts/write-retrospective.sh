#!/usr/bin/env bash
# A role's retrospective file, written at its close-out with retrospectives on
# (`process-review`'s `references/retrospective.md`, "When a retrospective is
# written").
#
#   write-retrospective.sh --begin
#   write-retrospective.sh <nonce> --role=<role> --issue=<URL> [--issue=<URL>…] --body=<file> [--root=<dir>]
#   write-retrospective.sh --post-usage=<file>
#
# `--begin` prints a fresh nonce on its first line, as `session-usage.sh
# --nonce` does, then a blank line and the "The prompt" section of
# retrospective.md, read from it as it runs. The second form is run from a
# later Bash call, given that nonce: a running call is not in the transcript
# until it returns, so only an earlier call's output can be found.
#
# The second form reads the usage as `session-usage.sh <nonce>` does, then
# writes `<root>/<owner>/<repo>/<YYYY-MM-DD>T<HHMMSS>Z-<n>-<role>.md`, in UTC:
#
#   ---
#   tags:
#     - retrospective
#     - <role>
#   role: <role>
#   issue: <URL>                  # several: a YAML list, one `  - <URL>` each
#   plugin_version: <version|none>
#   date: <YYYY-MM-DD>
#   usage:                        # UNKNOWN: usage: {result: UNKNOWN, reason: <reason>}
#     result: OK
#     scope: <session|self>
#     agent: <main|agentType>
#     requests: <n>
#     input: <n>
#     cache_write: <n>
#     cache_read: <n>
#     output: <n>
#   children:                     # only when there are `child=` lines
#     - agent: <agentType>
#       id: <agent id>
#       depth: <n>
#       parent: <session|agent id>
#       requests: <n>
#       input: <n>
#       cache_write: <n>
#       cache_read: <n>
#       output: <n>
#   ---
#
# then a blank line and the body file as given. `usage` holds the result
# line's fields, named as the line names them; `children` one entry per
# `child=` line, the `child=` value under `agent`.
#
# - `--role` is author, spec-author, reviewer, issue-reviewer or orchestrator.
# - `--issue` is a github.com issue or PR URL. Several are ordered by repo and
#   then number, whatever order they came in, and the first gives `<owner>`,
#   `<repo>` and `<n>`.
# - `--body` must carry exactly the five `## ` headings of "The prompt", in
#   its order; any other set is refused with nothing written.
# - `--root` defaults to ~/.claude/dnbg/retrospectives. Plugin options reach
#   hooks only, so the agent passes the root the session-start note names. It
#   must be absolute or start with `~/`.
# - `plugin_version` is the manifest's beside this script: the version whose
#   script ran.
#
# On `scope=session` it then posts the `Usage:` comment on the first issue, as
# the role's forge identity (author for author and spec-author, reviewer for
# reviewer and issue-reviewer, orchestrator), through as-role.sh. Its first
# line is exactly `Usage:`, then a blank line and a fenced block holding the
# result line and each `child=` line. `scope=self` and UNKNOWN post nothing: a
# dispatched agent's usage is in its dispatcher's `child=` lines.
#
# `--post-usage=<file>` posts that comment from a written file's frontmatter,
# the retry for a failed post.
#
# One result line, then exit 0:
#   result=OK path=<file> usage=<OK|UNKNOWN> usage_comment=<posted|none|failed>
#   result=OK path=<file> usage_comment=<posted|none|failed>      # --post-usage
#   result=ERROR reason=bad-args|unsupported-forge|bad-root|bad-body|no-prompt|exists|write|bad-file
#
# A failed post leaves the file written. `exists` is a file already at the
# path, never overwritten; `bad-file` a `--post-usage` file this script did not
# write.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB: the `FORGE` guard
# below refuses any other forge. The issue URLs are github.com ones.
set -euo pipefail
unset GH_TOKEN

HERE="$(cd "$(dirname "$0")" && pwd)"
REFERENCE="$HERE/../skills/process-review/references/retrospective.md"
MANIFEST="$HERE/../.claude-plugin/plugin.json"

fail() { echo "result=ERROR reason=$1"; exit 0; }

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

HEADINGS=$'## Slowed or blocked\n## Skill wrong or missing\n## Worked around\n## Wished to ask\n## Read but not used'

prompt_section() {  # -> "The prompt" section of retrospective.md, heading and all
  awk '/^## The prompt$/ { on = 1; print; next } on && /^## / { exit } on' "$REFERENCE" 2>/dev/null
}

forge_role() {  # <file role> -> the role the comment posts as
  case "$1" in
    author|spec-author) echo author ;;
    reviewer|issue-reviewer) echo reviewer ;;
    *) echo "$1" ;;
  esac
}

# Posts the `Usage:` comment. <lines> are the result line and the child lines.
post_usage() {  # <role> <url> <lines>
  local owner repo kind n fence='```'
  IFS=/ read -r owner repo kind n <<< "${2#https://github.com/}"
  case "$kind" in pull) kind="pr" ;; *) kind="issue" ;; esac
  if printf 'Usage:\n\n%s\n%s\n%s\n' "$fence" "$3" "$fence" |
       "$HERE/as-role.sh" "$(forge_role "$1")" "$owner/$repo" -- \
         gh "$kind" comment "$n" --repo "$owner/$repo" --body-file - >/dev/null 2>&1; then
    echo posted
  else
    echo failed
  fi
}

case "${1:-}" in
  --begin)
    [ "$#" -eq 1 ] || fail bad-args
    PROMPT=$(prompt_section)
    [ -n "$PROMPT" ] || fail no-prompt
    "$HERE/session-usage.sh" --nonce
    printf '\n%s\n' "$PROMPT"
    exit 0 ;;
  --post-usage=?*)
    [ "$#" -eq 1 ] || fail bad-args
    FILE="${1#--post-usage=}"
    [ -r "$FILE" ] || fail bad-file
    FRONT=$(awk 'NR == 1 { if ($0 != "---") exit; next } /^---$/ { exit } { print }' "$FILE")
    ROLE=$(printf '%s\n' "$FRONT" | sed -n 's/^role: //p')
    URL=$(printf '%s\n' "$FRONT" | awk '/^issue: https:/ { print $2; exit } /^issue:$/ { l = 1; next } l && /^  - / { print $2; exit }')
    # The usage block's fields, then each child's, as the lines they came from.
    LINES=$(printf '%s\n' "$FRONT" | awk '
      function kv(k, v) { sub(/:$/, "", k); return k "=" v }
      /^usage:$/    { sect = "u"; next }
      /^children:$/ { sect = "c"; next }
      /^[^ ]/       { sect = "" }
      sect == "u" && /^  [a-z_]+: /   { u = u (u ? " " : "") kv($1, $2) }
      sect == "c" && /^  - agent: /   { if (c) print c; c = "child=" $3; next }
      sect == "c" && /^    [a-z_]+: / { c = c " " kv($1, $2) }
      END { if (c) print c; print "U " u }')
    USAGE=$(printf '%s\n' "$LINES" | sed -n 's/^U //p')
    CHILDREN=$(printf '%s\n' "$LINES" | grep '^child=' || true)
    case "$ROLE:$URL" in
      ?*:https://github.com/*/*/*/[0-9]*) ;;
      *) fail bad-file ;;
    esac
    case "$USAGE" in
      "result=OK scope=session "*)
        LINES="$USAGE"; [ -z "$CHILDREN" ] || LINES="$LINES"$'\n'"$CHILDREN"
        echo "result=OK path=$FILE usage_comment=$(post_usage "$ROLE" "$URL" "$LINES")" ;;
      result=*) echo "result=OK path=$FILE usage_comment=none" ;;
      *) printf '%s\n' "$FRONT" | grep -q '^usage: {result: UNKNOWN' || fail bad-file
         echo "result=OK path=$FILE usage_comment=none" ;;
    esac
    exit 0 ;;
  ''|-*) fail bad-args ;;
esac

NONCE=$1; shift
ROLE=""; BODY=""; ROOT="$HOME/.claude/dnbg/retrospectives"; ISSUES=()
for a in "$@"; do
  case "$a" in
    --role=*)  ROLE="${a#--role=}" ;;
    --issue=*) ISSUES+=("${a#--issue=}") ;;
    --body=*)  BODY="${a#--body=}" ;;
    --root=*)
      ROOT="${a#--root=}"
      case "$ROOT" in
        \~/?*) ROOT="$HOME/${ROOT#\~/}" ;;
        /*) ;;
        *) fail bad-root ;;
      esac ;;
    *) fail bad-args ;;
  esac
done
case "$ROLE" in author|spec-author|reviewer|issue-reviewer|orchestrator) ;; *) fail bad-args ;; esac
[ "${#ISSUES[@]}" -gt 0 ] || fail bad-args
for u in "${ISSUES[@]}"; do
  [[ $u =~ ^https://github\.com/[^/]+/[^/]+/(issues|pull)/[0-9]+$ ]] || fail bad-args
done
[ -n "$BODY" ] && [ -r "$BODY" ] || fail bad-body
[ "$(grep '^## ' "$BODY" || true)" = "$HEADINGS" ] || fail bad-body

# By owner, repo, then number: the URL's fields 4, 5 and 7 split on `/`.
SORTED=()
while IFS= read -r u; do SORTED+=("$u"); done < <(printf '%s\n' "${ISSUES[@]}" | sort -u -t/ -k4,4 -k5,5 -k7,7n)
IFS=/ read -r OWNER NAME _ N <<< "${SORTED[0]#https://github.com/}"

USAGE_OUT=$("$HERE/session-usage.sh" "$NONCE")
USAGE=$(printf '%s\n' "$USAGE_OUT" | head -1)
CHILDREN=$(printf '%s\n' "$USAGE_OUT" | grep '^child=' || true)
VERSION=$(jq -r '.version // empty' "$MANIFEST" 2>/dev/null) || VERSION=""

STAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
DIR="$ROOT/$OWNER/$NAME"
FILE="$DIR/$STAMP-$N-$ROLE.md"

frontmatter() {
  local kv
  printf -- '---\ntags:\n  - retrospective\n  - %s\nrole: %s\n' "$ROLE" "$ROLE"
  if [ "${#SORTED[@]}" -eq 1 ]; then
    printf 'issue: %s\n' "${SORTED[0]}"
  else
    printf 'issue:\n'; printf '  - %s\n' "${SORTED[@]}"
  fi
  printf 'plugin_version: %s\ndate: %s\n' "${VERSION:-none}" "${STAMP:0:10}"
  case "$USAGE" in
    result=OK\ *)
      printf 'usage:\n'
      for kv in $USAGE; do printf '  %s: %s\n' "${kv%%=*}" "${kv#*=}"; done
      if [ -n "$CHILDREN" ]; then
        printf 'children:\n'
        while IFS= read -r line; do
          local first=1
          for kv in $line; do
            if [ "$first" = 1 ]; then printf '  - agent: %s\n' "${kv#child=}"; first=0
            else printf '    %s: %s\n' "${kv%%=*}" "${kv#*=}"; fi
          done
        done <<< "$CHILDREN"
      fi ;;
    *) printf 'usage: {result: UNKNOWN, reason: %s}\n' "$(printf '%s' "$USAGE" | sed -n 's/.*reason=\([^ ]*\).*/\1/p')" ;;
  esac
  printf -- '---\n\n'
}

mkdir -p "$DIR" 2>/dev/null || fail write
[ ! -e "$FILE" ] || fail exists
# Written beside the file under a name process-review's `*.md` never reads,
# then linked into place, so no half-written file joins a batch and a link
# refuses one already written in the same second.
PARTIAL="$DIR/.${FILE##*/}.partial.$$"
{ frontmatter; cat "$BODY"; } > "$PARTIAL" 2>/dev/null || fail write
ln "$PARTIAL" "$FILE" 2>/dev/null || { rm -f "$PARTIAL"; fail exists; }
rm -f "$PARTIAL"

case "$USAGE" in
  "result=OK scope=session "*)
    LINES="$USAGE"; [ -z "$CHILDREN" ] || LINES="$LINES"$'\n'"$CHILDREN"
    COMMENT=$(post_usage "$ROLE" "${SORTED[0]}" "$LINES") ;;
  *) COMMENT=none ;;
esac
RESULT=${USAGE#result=}
echo "result=OK path=$FILE usage=${RESULT%% *} usage_comment=$COMMENT"
