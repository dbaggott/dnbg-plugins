#!/usr/bin/env bash
# Moves every file under <from> to the same relative path under <to>, creating
# <to> as needed, then removes the directories that leaves empty, <from> among
# them. A file already at its path under <to> is never overwritten: it stays in
# <from> and is named on stdout, and the exit status is then 1.
#
#   move-legacy-dir.sh <from> <to>
#
# The legacy-directory notice prints this command for the user to run.
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: move-legacy-dir.sh <from> <to>" >&2; exit 2; }
from=${1%/} to=${2%/}
case "$to" in /*) ;; *) to="$PWD/$to" ;; esac
case "$to/" in "$from"/*) echo "$to is inside $from" >&2; exit 2 ;; esac

skipped=0
while IFS= read -r -d '' path; do
  rel=${path#"$from"/}
  if [ -e "$to/$rel" ]; then
    echo "skipped: $path (already in $to)"
    skipped=1
    continue
  fi
  mkdir -p "$(dirname "$to/$rel")"
  mv "$path" "$to/$rel"
done < <(find "$from" -type f -print0)

find "$from" -depth -type d -empty -delete
exit "$skipped"
