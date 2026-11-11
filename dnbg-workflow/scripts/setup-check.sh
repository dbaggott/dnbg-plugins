#!/usr/bin/env bash
# What a dnbg-workflow install still needs, for the `setup` skill. Read-only.
#
#   setup-check.sh [--owners=<value>] [--retrospectives=<value>] [--version-stamp=<value>]
#
# One line per check, then exactly one result line, then exit 0:
#   check=tools state=<ok|missing> missing=<tool,…|none>
#   check=gh-auth state=<ok|none|unknown>
#   check=claude-code state=<ok|below|unknown> version=<x.y.z|unknown> floor=<x.y.z>
#   check=owners state=<set|empty> [value=<owner,…>]
#   check=roles state=<ok|unconfigured|error|unknown> configured=<role,…|none> fallback=<role,…|none> unconfigured=<role,…|none> [reason=<reason>]
#   check=retrospectives state=<on|off>
#   check=version-stamp state=<on|off>
#   check=plugins state=<ok|unknown> self=<plugin@marketplace|none> installed=<plugin,…|none>
#   check=marker acknowledged=<owners,roles|owners|roles|none> path=<path>
#   result=OK setup=<complete|incomplete> open=<check,…|none>
#   result=ERROR reason=bad-args
#
# `open` names the checks that leave setup incomplete: `tools` missing,
# `gh-auth` none, `claude-code` below, `owners` empty, and `roles` unconfigured
# or error. `unknown` is a check that could not be read, and is never open:
# `gh-auth` without `gh`, `claude-code` without a `claude` on PATH that prints a
# version, `roles` and `plugins` without `jq`, `plugins` without Claude Code's
# record of installs. `retrospectives`, `version-stamp`, `plugins` and `marker`
# are never open.
#
# The three options are the plugin's own, which reach a hook as
# CLAUDE_PLUGIN_OPTION_* and reach no script an agent runs, so the skill passes
# each from `${user_config.<key>}` in its own text. An option nobody has set
# substitutes nothing there, so a value that is still that placeholder is read
# as unset, as an empty one and an absent flag are.
#
# `roles` is `as-role.sh --roles`, whose ERROR reason is passed through.
# `gh-auth` asks `gh` for its stored login with no token in the environment, as
# the resolver reads the operator's, and makes no network call. `plugins` reads
# Claude Code's record of installs at any scope, `plugins/installed_plugins.json`
# under its config directory: `self` is the id of the install this script is
# running from, matched on its path, which `claude plugin configure` takes, and
# `installed` lists which of its marketplace's other plugins are there. A copy
# loaded with `--plugin-dir` is not a recorded install, so its `self` is `none`
# whatever else is installed. `marker` is the file the `setup` skill appends
# `owners` or `roles` to when the user leaves that one unset on purpose, which
# stops the session-start nudge for it; `acknowledged` is what it holds.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

TOOLS="jq git gh python3 openssl curl"
SIBLING_PLUGINS="dnbg-practices dnbg-work-summary dnbg-agent-summaries"
# The floor docs/requirements.md states; tests/coupling.bats holds the two equal.
CLAUDE_CODE_FLOOR=2.1.207

OWNERS=""; RETROSPECTIVES=""; VERSION_STAMP=""
for arg in "$@"; do
  case "$arg" in
    --owners=*) OWNERS="${arg#*=}" ;;
    --retrospectives=*) RETROSPECTIVES="${arg#*=}" ;;
    --version-stamp=*) VERSION_STAMP="${arg#*=}" ;;
    *) echo "result=ERROR reason=bad-args"; exit 0 ;;
  esac
done

# shellcheck disable=SC2016  # the placeholder is matched as literal text
unset_if_placeholder() {  # <value>
  case "$1" in '${user_config.'*) ;; *) printf '%s' "$1" ;; esac
}

on_or_off() {  # <value>
  case "$(unset_if_placeholder "$1")" in [Tt][Rr][Uu][Ee]) echo on ;; *) echo off ;; esac
}

has() { command -v "$1" >/dev/null 2>&1; }

OPEN=""
open() { OPEN="${OPEN:+$OPEN,}$1"; }

MISSING=""
for tool in $TOOLS; do
  has "$tool" || MISSING="${MISSING:+$MISSING,}$tool"
done
if [ -z "$MISSING" ]; then
  echo "check=tools state=ok missing=none"
else
  echo "check=tools state=missing missing=$MISSING"; open tools
fi

if ! has gh; then
  echo "check=gh-auth state=unknown"
elif env -u GH_TOKEN -u GITHUB_TOKEN gh auth token </dev/null >/dev/null 2>&1; then
  echo "check=gh-auth state=ok"
else
  echo "check=gh-auth state=none"; open gh-auth
fi

# 0 when <a> is at or above <b>, both x.y.z.
version_at_least() {  # <a> <b>
  local a b i
  IFS=. read -ra a <<<"$1"; IFS=. read -ra b <<<"$2"
  for i in 0 1 2; do
    [ "${a[i]}" -gt "${b[i]}" ] && return 0
    [ "${a[i]}" -lt "${b[i]}" ] && return 1
  done
  return 0
}

VERSION=""
if has claude; then
  RAW=$(claude --version 2>/dev/null </dev/null || true)
  [[ "$RAW" =~ ^([0-9]+\.[0-9]+\.[0-9]+) ]] && VERSION="${BASH_REMATCH[1]}"
fi
if [ -z "$VERSION" ]; then
  echo "check=claude-code state=unknown version=unknown floor=$CLAUDE_CODE_FLOOR"
elif version_at_least "$VERSION" "$CLAUDE_CODE_FLOOR"; then
  echo "check=claude-code state=ok version=$VERSION floor=$CLAUDE_CODE_FLOOR"
else
  echo "check=claude-code state=below version=$VERSION floor=$CLAUDE_CODE_FLOOR"; open claude-code
fi

# Set means it names an owner: the hooks strip whitespace before matching, and
# commas alone name nobody. `value` is the list as they read it, kept to the
# characters a GitHub login can hold.
OWNERS=$(unset_if_placeholder "$OWNERS")
OWNERS="${OWNERS//[^[:alnum:],_.-]/}"
if [ -n "${OWNERS//,/}" ]; then
  echo "check=owners state=set value=$OWNERS"
else
  echo "check=owners state=empty"; open owners
fi

if ! has jq; then
  echo "check=roles state=unknown configured=none fallback=none unconfigured=none"
else
  LINE=$("$HERE/as-role.sh" --roles 2>/dev/null || true)
  case "$LINE" in
    "result=OK configured="*" unconfigured=none")
      echo "check=roles state=ok ${LINE#result=OK }" ;;
    "result=OK configured="*)
      echo "check=roles state=unconfigured ${LINE#result=OK }"; open roles ;;
    "result=ERROR reason="*)
      echo "check=roles state=error configured=none fallback=none unconfigured=none ${LINE#result=ERROR }"; open roles ;;
    *)
      echo "check=roles state=error configured=none fallback=none unconfigured=none reason=no-answer"; open roles ;;
  esac
fi

echo "check=retrospectives state=$(on_or_off "$RETROSPECTIVES")"
echo "check=version-stamp state=$(on_or_off "$VERSION_STAMP")"

RECORD="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/plugins/installed_plugins.json"
if has jq && KEYS=$(jq -r '.plugins | keys[]' "$RECORD" 2>/dev/null); then
  ROOT=$(cd "$HERE/.." && pwd)
  SELF=$(jq -r --arg a "$ROOT" --arg b "$(cd "$ROOT" && pwd -P)" '
    first(.plugins | to_entries[]
          | select(any(.value[]?; .installPath == $a or .installPath == $b)) | .key) // empty' \
    "$RECORD" 2>/dev/null || true)
  INSTALLED=""
  for plugin in $SIBLING_PLUGINS; do
    case $'\n'"$KEYS" in *$'\n'"$plugin@"*) INSTALLED="${INSTALLED:+$INSTALLED,}$plugin" ;; esac
  done
  echo "check=plugins state=ok self=${SELF:-none} installed=${INSTALLED:-none}"
else
  echo "check=plugins state=unknown self=none installed=none"
fi

MARKER="${XDG_CONFIG_HOME:-${HOME:-}/.config}/dnbg/setup-acknowledged"
ACKNOWLEDGED=""
if [ -r "$MARKER" ]; then
  while IFS= read -r line; do
    case "$line" in owners|roles)
      case ",$ACKNOWLEDGED," in *",$line,"*) ;; *) ACKNOWLEDGED="${ACKNOWLEDGED:+$ACKNOWLEDGED,}$line" ;; esac ;;
    esac
  done < "$MARKER"
fi
echo "check=marker acknowledged=${ACKNOWLEDGED:-none} path=$MARKER"

if [ -z "$OPEN" ]; then
  echo "result=OK setup=complete open=none"
else
  echo "result=OK setup=incomplete open=$OPEN"
fi
