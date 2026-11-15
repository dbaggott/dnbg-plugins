#!/usr/bin/env bats
#
# Tests for the post-merge cleanup. Each runs against a real checkout whose
# `origin` is a bare repository at `<tmp>/acme/r.git`, so it reads as acme/r.
# `gh` is stubbed: the PR and the repo settings come from files the test
# writes, `--jq` is applied to them with the real jq, and the remote branch
# deletion is recorded rather than sent. No role is configured, so the author
# falls back to the operator.

bats_require_minimum_version 1.5.0

POST_MERGE="${BATS_TEST_DIRNAME}/../dnbg-workflow/scripts/post-merge.sh"

setup() {
  local v
  for v in $(compgen -v DNBG_); do unset "$v"; done
  unset GH_TOKEN GITHUB_TOKEN
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg"; mkdir -p "$XDG_CONFIG_HOME"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  export PR_JSON="$BATS_TEST_TMPDIR/pr.json" REPO_JSON="$BATS_TEST_TMPDIR/repo.json"
  export REFS_JSON="$BATS_TEST_TMPDIR/refs.json" DELETE_FAIL="$BATS_TEST_TMPDIR/delete-fail"
  echo '[]' > "$REFS_JSON"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
jq_of() {  # <json file> <args…> — applies any --jq in the args
  local prev="" expr="."
  for a in "$@"; do [ "$prev" != --jq ] || expr=$a; prev=$a; done
  jq -r "$expr" "$1"
}
case "$1 $2" in
  "pr view") cat "$PR_JSON" ;;
  "api user") echo operator-login ;;
  "api -X") [ ! -e "$DELETE_FAIL" ] ;;
  "api repos/acme/r") shift 2; jq_of "$REPO_JSON" "$@" ;;
  "api repos/acme/r/git/matching-refs/"*) shift 2; jq_of "$REFS_JSON" "$@" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"

  # Resolved, since git reports a worktree's path with symlinks resolved.
  TMP=$(cd "$BATS_TEST_TMPDIR" && pwd -P)
  ORIGIN="$TMP/acme/r.git"
  CHECKOUT="$TMP/checkout"
  git init -q --bare -b main "$ORIGIN"
  git init -q -b main "$CHECKOUT"
  git -C "$CHECKOUT" remote add origin "$ORIGIN"
  git -C "$CHECKOUT" commit -q --allow-empty -m base
  git -C "$CHECKOUT" push -q -u origin main
}

pr() {  # <state> [auto-merge: scheduled|none]
  jq -n --arg s "$1" --arg a "${2:-none}" \
    '{state: $s, headRefName: "feature", autoMergeRequest: (if $a == "scheduled" then {mergeMethod: "SQUASH"} else null end)}' > "$PR_JSON"
}

settings() {  # <allow_squash_merge> <delete_branch_on_merge>
  jq -n --argjson s "$1" --argjson d "$2" \
    '{default_branch: "main", allow_squash_merge: $s, delete_branch_on_merge: $d}' > "$REPO_JSON"
}

# The feature branch, checked out in a worktree at <path>, one commit ahead of
# main; with `merged`, main is fast-forwarded onto it on the origin, as a merge
# commit leaves the branch an ancestor of the base, and without it the branch
# is left unmerged locally, as a squash leaves it.
feature() {  # <worktree path> [merged]
  git -C "$CHECKOUT" worktree add -q "$1" -b feature main
  git -C "$1" commit -q --allow-empty -m work
  git -C "$1" push -q origin feature
  if [ "${2:-}" = merged ]; then
    git -C "$1" push -q origin feature:main
  else
    git -C "$CHECKOUT" commit -q --allow-empty -m squashed
    git -C "$CHECKOUT" push -q origin main
    git -C "$CHECKOUT" reset -q --hard HEAD~1
  fi
}

run_cleanup() {
  run --separate-stderr bash -c 'cd "$1" && "$2" acme/r 7' _ "$CHECKOUT" "$POST_MERGE"
}

@test "a squash-merging repo deletes the unmerged local branch with -D" {
  pr MERGED; settings true true
  feature "$CHECKOUT/.worktrees/feature"
  run_cleanup
  [ "$output" = "$(printf '%s\n' \
    "step=worktree result=removed path=$CHECKOUT/.worktrees/feature" \
    "step=switch result=ok branch=main" "step=pull result=ok" \
    "step=branch result=deleted flag=-D" "step=remote result=by-repo" \
    "result=OK pr=7 branch=feature")" ]
  [ ! -e "$CHECKOUT/.worktrees/feature" ]
  ! git -C "$CHECKOUT" show-ref --verify --quiet refs/heads/feature || false
  [ "$(git -C "$CHECKOUT" rev-parse main)" = "$(git -C "$ORIGIN" rev-parse main)" ]
}

@test "a repo that does not squash deletes the merged branch with -d" {
  pr MERGED; settings false true
  feature "$CHECKOUT/.worktrees/feature" merged
  run_cleanup
  [[ $output == *"step=branch result=deleted flag=-d"* ]]
  [[ ${lines[-1]} == "result=OK pr=7 branch=feature" ]]
}

@test "a worktree outside .worktrees/ is found and removed" {
  pr MERGED; settings true true
  feature "$TMP/elsewhere/wt"
  run_cleanup
  [ "${lines[0]}" = "step=worktree result=removed path=$TMP/elsewhere/wt" ]
  [ ! -e "$TMP/elsewhere/wt" ]
  [ "${lines[-1]}" = "result=OK pr=7 branch=feature" ]
}

@test "delete_branch_on_merge off deletes the remote branch as the author" {
  pr MERGED; settings true false
  feature "$CHECKOUT/.worktrees/feature"
  run_cleanup
  [[ $output == *"step=remote result=deleted"* ]]
  grep -qx 'api -X DELETE repos/acme/r/git/refs/heads/feature' "$CALLS"
  [ "${lines[-1]}" = "result=OK pr=7 branch=feature" ]
}

@test "delete_branch_on_merge on makes no delete call" {
  pr MERGED; settings true true
  feature "$CHECKOUT/.worktrees/feature"
  run_cleanup
  [[ $output == *"step=remote result=by-repo"* ]]
  ! grep -q -- '-X DELETE' "$CALLS" || false
}

@test "a remote branch already gone counts as done, and one still there as failed" {
  pr MERGED; settings true false
  feature "$CHECKOUT/.worktrees/feature"
  touch "$DELETE_FAIL"
  run_cleanup
  [[ $output == *"step=remote result=absent"* ]]
  [ "${lines[-1]}" = "result=OK pr=7 branch=feature" ]

  git -C "$CHECKOUT" branch -q feature main
  echo '[{"ref": "refs/heads/feature"}]' > "$REFS_JSON"
  run_cleanup
  [[ $output == *"step=remote result=failed"* ]]
  [ "${lines[-1]}" = "result=FAILED failed=remote pr=7 branch=feature" ]
}

@test "a worktree already gone counts as done, and is pruned" {
  pr MERGED; settings true true
  feature "$CHECKOUT/.worktrees/feature"
  rm -rf "$CHECKOUT/.worktrees/feature"
  run_cleanup
  [ "${lines[0]}" = "step=worktree result=absent path=$CHECKOUT/.worktrees/feature" ]
  [[ $output == *"step=branch result=deleted flag=-D"* ]]
  [ "${lines[-1]}" = "result=OK pr=7 branch=feature" ]
  ! git -C "$CHECKOUT" worktree list --porcelain | grep -q feature || false
}

@test "a failed pull still deletes the branch, and the result line names the pull" {
  pr MERGED; settings true true
  feature "$CHECKOUT/.worktrees/feature"
  # Local main diverges from the origin's, so the fast-forward is refused.
  git -C "$CHECKOUT" commit -q --allow-empty -m local-only
  run_cleanup
  [[ $output == *"step=pull result=failed"* ]]
  [[ $output == *"step=branch result=deleted flag=-D"* ]]
  [ "${lines[-1]}" = "result=FAILED failed=pull pr=7 branch=feature" ]
}

@test "an open PR removes nothing and says whether auto-merge is scheduled" {
  pr OPEN scheduled; settings true true
  feature "$CHECKOUT/.worktrees/feature"
  run_cleanup
  [ "$output" = "result=NOT-MERGED state=OPEN auto_merge=scheduled" ]
  [ -d "$CHECKOUT/.worktrees/feature" ]
  git -C "$CHECKOUT" show-ref --verify --quiet refs/heads/feature
  ! grep -q '^api repos' "$CALLS" || false
}

@test "a PR closed unmerged removes nothing" {
  pr CLOSED; settings true true
  feature "$CHECKOUT/.worktrees/feature"
  run_cleanup
  [ "$output" = "result=NOT-MERGED state=CLOSED auto_merge=none" ]
  [ -d "$CHECKOUT/.worktrees/feature" ]
}

@test "run from inside the worktree, the steps still run in the main checkout" {
  pr MERGED; settings true true
  feature "$CHECKOUT/.worktrees/feature"
  run --separate-stderr bash -c 'cd "$1" && "$2" acme/r 7' _ "$CHECKOUT/.worktrees/feature" "$POST_MERGE"
  [ "${lines[-1]}" = "result=OK pr=7 branch=feature" ]
  [ "$(git -C "$CHECKOUT" branch --show-current)" = main ]
}

@test "a checkout of another repo is refused before anything runs" {
  pr MERGED; settings true true
  feature "$CHECKOUT/.worktrees/feature"
  run --separate-stderr bash -c 'cd "$1" && "$2" acme/other 7' _ "$CHECKOUT" "$POST_MERGE"
  [ "$output" = "result=ERROR reason=wrong-repo" ]
  [ -d "$CHECKOUT/.worktrees/feature" ]
  [ ! -s "$CALLS" ]
}
