#!/usr/bin/env bash
# The cleanup after a PR merges, from `git-workflow`'s `references/post-merge.md`.
#
#   post-merge.sh <owner/repo> <pr>
#
# Run it from the repo's checkout; the git steps run in its main worktree,
# whichever of its worktrees the call is made from. It reads the PR's state, and
# unless it is MERGED removes nothing and prints one line, then exits 0:
#   result=NOT-MERGED state=<OPEN|CLOSED> auto_merge=<scheduled|none>
#
# On MERGED it runs five steps, each printing one line, then a result line:
#   step=worktree result=removed|absent|failed path=<path|none>
#   step=switch result=ok|failed branch=<default branch>
#   step=pull result=ok|failed|skipped
#   step=branch result=deleted|absent|failed flag=<-D|-d>
#   step=remote result=deleted|absent|by-repo|failed
#   result=OK pr=<n> branch=<head branch>
#   result=FAILED failed=<step,…> pr=<n> branch=<head branch>
#
# - worktree: the worktree that has the PR's head branch checked out, found
#   with `git worktree list --porcelain` because the worktree root is
#   configurable and the option reaches no script an agent runs. None is
#   `absent`; one whose directory is already gone is pruned and also `absent`.
# - switch, pull: the main worktree onto the default branch, then
#   `git pull --ff-only --prune`. The pull is `skipped` when the switch failed,
#   since it would fast-forward the wrong branch.
# - branch: the local branch, with `-D` where the repo allows squash merges (a
#   squashed branch's tip is never an ancestor of the base, so `-d` refuses)
#   and `-d` otherwise.
# - remote: `by-repo` where `delete_branch_on_merge` is on, else deleted as the
#   author role through as-role.sh, which pushed it; a branch already gone is
#   `absent`.
#
# Each step runs even when an earlier one failed, wherever it still can, so a
# failed pull still deletes the branch. Git's own errors go to stderr.
#
#   result=ERROR reason=bad-args|unsupported-forge|not-a-checkout|wrong-repo|pr-query|repo-query
#
# `wrong-repo` is a checkout whose `origin` is not <owner/repo>; nothing ran.
#
# ⚠️ THE FORGE IS ASSUMED TO BE GITHUB: the `FORGE` guard below refuses any
# other forge.
set -euo pipefail
unset GH_TOKEN

fail() { echo "result=ERROR reason=$1"; exit 0; }

REPO="${1:-}"; PR="${2:-}"
[ "$#" -eq 2 ] || fail bad-args
case "$REPO" in */*/*|/*|*/) fail bad-args ;; */*) ;; *) fail bad-args ;; esac
case "$PR" in ''|*[!0-9]*) fail bad-args ;; esac

FORGE="${FORGE:-github}"
[ "$FORGE" = github ] || fail unsupported-forge

# The main worktree is the first entry git lists.
MAIN=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p') || true
[ -n "$MAIN" ] || fail not-a-checkout
ORIGIN=$(git -C "$MAIN" remote get-url origin 2>/dev/null) || fail not-a-checkout
# https://github.com/o/r(.git), ssh://git@github.com/o/r.git, git@github.com:o/r.git
ORIGIN=${ORIGIN%.git}; ORIGIN=${ORIGIN%/}
ORIGIN_NAME=${ORIGIN##*/}; ORIGIN=${ORIGIN%/*}; ORIGIN_OWNER=${ORIGIN##*[/:]}
[ "$ORIGIN_OWNER/$ORIGIN_NAME" = "$REPO" ] || fail wrong-repo

PRJSON=$(gh pr view "$PR" --repo "$REPO" --json state,autoMergeRequest,headRefName 2>/dev/null) || fail pr-query
IFS=$'\t' read -r STATE AUTO BRANCH < <(printf '%s' "$PRJSON" | jq -r '
  [.state, (if .autoMergeRequest == null then "none" else "scheduled" end), .headRefName] | @tsv' 2>/dev/null) || fail pr-query
case "$STATE" in OPEN|CLOSED|MERGED) ;; *) fail pr-query ;; esac
[ -n "$BRANCH" ] || fail pr-query
if [ "$STATE" != MERGED ]; then
  echo "result=NOT-MERGED state=$STATE auto_merge=$AUTO"
  exit 0
fi

SETTINGS=$(gh api "repos/$REPO" --jq '[.default_branch, .allow_squash_merge, .delete_branch_on_merge] | @tsv' 2>/dev/null) || fail repo-query
IFS=$'\t' read -r DEFAULT SQUASH DELETE_ON_MERGE <<< "$SETTINGS"
[ -n "$DEFAULT" ] || fail repo-query

FAILED=()

# The worktree: every entry after the main one, as `<path>\t<branch ref>\t<prunable 0|1>`.
WT=""; WT_GONE=0
while IFS=$'\t' read -r path ref gone; do
  [ "$ref" = "refs/heads/$BRANCH" ] || continue
  WT=$path; WT_GONE=$gone
done < <(git -C "$MAIN" worktree list --porcelain | awk '
  /^worktree / { if (n++) print p "\t" r "\t" g; p = substr($0, 10); r = ""; g = 0 }
  /^branch /   { r = substr($0, 8) }
  /^prunable/  { g = 1 }
  END          { if (n > 1) print p "\t" r "\t" g }' | tail -n +2)
if [ -z "$WT" ]; then
  echo "step=worktree result=absent path=none"
elif [ "$WT_GONE" = 1 ]; then
  git -C "$MAIN" worktree prune >&2 || true
  echo "step=worktree result=absent path=$WT"
elif git -C "$MAIN" worktree remove "$WT" >&2; then
  echo "step=worktree result=removed path=$WT"
else
  echo "step=worktree result=failed path=$WT"; FAILED+=(worktree)
fi

if git -C "$MAIN" switch "$DEFAULT" >&2; then
  echo "step=switch result=ok branch=$DEFAULT"
  if git -C "$MAIN" pull --ff-only --prune >&2; then
    echo "step=pull result=ok"
  else
    echo "step=pull result=failed"; FAILED+=(pull)
  fi
else
  echo "step=switch result=failed branch=$DEFAULT"; FAILED+=(switch)
  echo "step=pull result=skipped"
fi

FLAG=-d; [ "$SQUASH" = true ] && FLAG=-D
if ! git -C "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "step=branch result=absent flag=$FLAG"
elif git -C "$MAIN" branch "$FLAG" "$BRANCH" >&2; then
  echo "step=branch result=deleted flag=$FLAG"
else
  echo "step=branch result=failed flag=$FLAG"; FAILED+=(branch)
fi

remote_left() {  # -> 0 when the head branch still exists on the forge
  local n
  n=$(gh api "repos/$REPO/git/matching-refs/heads/$BRANCH" \
        --jq "[.[] | select(.ref == \"refs/heads/$BRANCH\")] | length" 2>/dev/null) || return 0
  [ "$n" != 0 ]
}
if [ "$DELETE_ON_MERGE" = true ]; then
  echo "step=remote result=by-repo"
elif "$(dirname "$0")/as-role.sh" author "$REPO" -- \
       gh api -X DELETE "repos/$REPO/git/refs/heads/$BRANCH" >/dev/null 2>&1; then
  echo "step=remote result=deleted"
elif ! remote_left; then
  echo "step=remote result=absent"
else
  echo "step=remote result=failed"; FAILED+=(remote)
fi

if [ "${#FAILED[@]}" -eq 0 ]; then
  echo "result=OK pr=$PR branch=$BRANCH"
else
  echo "result=FAILED failed=$(IFS=,; echo "${FAILED[*]}") pr=$PR branch=$BRANCH"
fi
