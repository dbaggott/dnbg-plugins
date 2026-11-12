#!/usr/bin/env bats
#
# Tests for role App setup. bootstrap.py runs in a copy of the plugin beside
# fixture roles (role-tree.bash), with GitHub's half of the Manifest flow and the
# browser click replaced by fixtures/bootstrap/drive.py, so what is under test is
# the loop over roles: which it creates or connects, from which permissions, into
# which dir. drive.py's header says what a world file holds.

load role-tree

setup() {
  make_role_tree
  add_role author operator
  MANIFESTS="$BATS_TEST_TMPDIR/manifests"; : > "$MANIFESTS"
  PORT=$((20000 + RANDOM % 20000))
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/Downloads"
  REVIEWER_DIR="$XDG_CONFIG_HOME/dnbg/reviewer"
}

# The world file drive.py answers from.
github() {
  export BOOTSTRAP_GITHUB="$BATS_TEST_TMPDIR/github.json"
  printf '%s' "$1" > "$BOOTSTRAP_GITHUB"
}

# The run's JSON, which `run` leaves after the stderr lines.
summary() {
  printf '%s\n' "$output" | sed -n '/^\[/,$p'
}

# The reviewer App of the login drive.py answers with, and a key of its own.
YOURS='"apps":{"agent-reviewer-tester":{"id":7,"owner":"tester"}},"keys":{"KEY-7":"agent-reviewer-tester"}'

# <role dir>: holds what a create writes, at a create's modes.
assert_saved() {
  [ "$(find -L "$1" -maxdepth 0 -perm 700 | wc -l)" -eq 1 ]
  [ "$(find -L "$1/private-key.pem" "$1/config.json" -perm 600 | wc -l)" -eq 2 ]
}

bootstrap() {
  run python3 "$BATS_TEST_DIRNAME/fixtures/bootstrap/drive.py" \
    "$TREE/skills/reviewer-setup" "$MANIFESTS" --port "$PORT" --timeout 20 "$@"
}

@test "a chosen subset of roles each gets its own App, in its own config dir" {
  bootstrap --roles reviewer,author
  [ "$status" -eq 0 ]
  [ "$(jq -r '.slug' "$XDG_CONFIG_HOME/dnbg/reviewer/config.json")" = agent-reviewer-tester ]
  [ "$(jq -r '.slug' "$XDG_CONFIG_HOME/dnbg/author/config.json")" = agent-author-tester ]
  [ "$(cat "$XDG_CONFIG_HOME/dnbg/author/private-key.pem")" = "PEM for agent-author-tester" ]
  [ "$(find -L "$XDG_CONFIG_HOME/dnbg/author" -maxdepth 0 -perm 700 | wc -l)" -eq 1 ]
}

@test "each manifest carries its own role's permissions" {
  bootstrap --roles reviewer,author
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$MANIFESTS" | jq -c .default_permissions)" = "$(jq -c .required "$TREE/roles/reviewer/permissions.json")" ]
  [ "$(sed -n 2p "$MANIFESTS" | jq -c .default_permissions)" = "$(jq -c .required "$TREE/roles/author/permissions.json")" ]
}

@test "a role left out is not created" {
  bootstrap --roles author
  [ "$status" -eq 0 ]
  [ -f "$XDG_CONFIG_HOME/dnbg/author/config.json" ]
  [ ! -e "$XDG_CONFIG_HOME/dnbg/reviewer" ]
  [ "$(wc -l < "$MANIFESTS")" -eq 1 ]
}

@test "by default every role not yet set up is created, and the rest skipped" {
  mkdir -p "$XDG_CONFIG_HOME/dnbg/reviewer"; echo '{"slug":"existing"}' > "$XDG_CONFIG_HOME/dnbg/reviewer/config.json"
  bootstrap
  [ "$status" -eq 0 ]
  [ "$(jq -r .slug "$XDG_CONFIG_HOME/dnbg/reviewer/config.json")" = existing ]
  [ "$(jq -r .slug "$XDG_CONFIG_HOME/dnbg/author/config.json")" = agent-author-tester ]
}

@test "an unknown role is refused before any App is created" {
  bootstrap --roles author,nobody
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown role(s) nobody"* ]]
  [ ! -s "$MANIFESTS" ]
}

@test "--name applies to one role only" {
  bootstrap --roles reviewer,author --name x
  [ "$status" -eq 2 ]
  [ ! -s "$MANIFESTS" ]
}

@test "a role set up through its variables alone counts as set up" {
  export DNBG_REVIEWER_APP_ID=42
  bootstrap
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME/dnbg/reviewer" ]
  [ -f "$XDG_CONFIG_HOME/dnbg/author/config.json" ]
}

@test "a config dir under ~/ is read from \$HOME" {
  export HOME="$BATS_TEST_TMPDIR/home" DNBG_AUTHOR_CONFIG_DIR='~/author'
  bootstrap --roles author
  [ "$status" -eq 0 ]
  [ -f "$HOME/author/config.json" ]
}

@test "a ~user config dir is refused before any App is created" {
  export DNBG_AUTHOR_CONFIG_DIR='~alice/author'
  bootstrap --roles reviewer,author
  [ "$status" -eq 1 ]
  [[ "$output" == *"DNBG_AUTHOR_CONFIG_DIR is '~alice/author'"* ]]
  [ ! -s "$MANIFESTS" ]
}

@test "another role's ~user config dir is refused too, since every role call would be" {
  export DNBG_AUTHOR_CONFIG_DIR='~alice/author'
  bootstrap --roles reviewer
  [ "$status" -eq 1 ]
  [[ "$output" == *"DNBG_AUTHOR_CONFIG_DIR is '~alice/author'"* ]]
  [ ! -s "$MANIFESTS" ]
}

@test "a role directory the resolver would refuse is not set up" {
  mkdir -p "$TREE/roles/Odd_Name"; cp "$TREE/roles/author/permissions.json" "$TREE/roles/Odd_Name/"
  bootstrap --roles Odd_Name
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown role(s) Odd_Name"* ]]
}

# The run opens the next role's tab the moment one App exists, so an install
# button on an earlier page is left in a tab nobody is looking at.
@test "the install buttons are on a run's last page, or on the page of the role that stopped it" {
  run python3 - "$BATS_TEST_DIRNAME/../dnbg-workflow/skills/reviewer-setup/bootstrap.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("bootstrap", sys.argv[1])
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
url = "https://github.com/apps/agent-%s-t/installations/new"
mid = b.created_page([("reviewer", url % "reviewer")], ["author", "orchestrator"])
assert "installations/new" not in mid and "author bot is next" in mid, mid
last = b.created_page([(r, url % r) for r in ("reviewer", "author", "orchestrator")], [])
assert all(url % r in last for r in ("reviewer", "author", "orchestrator")), last
assert "All 3 bots are created" in last, last
untabbed = b.created_page([("reviewer", url % "reviewer")], ["author"], tabs=False)
assert 'href="/start/author"' in untabbed and "installations/new" not in untabbed, untabbed
failed = b.failed_page("Setup failed", "no <code>", [("reviewer", url % "reviewer")])
assert url % "reviewer" in failed and "no &lt;code&gt;" in failed, failed
assert "installations/new" not in b.failed_page("Setup failed", "x", [])
one = b.created_page([("reviewer", url % "reviewer")], [])
assert one.count("installations/new") == 1 and "The reviewer bot is created" in one, one
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "--detect reports a bot of the operator's as yours and the rest as free, and changes nothing" {
  github "{$YOURS}"
  bootstrap --detect
  [ "$status" -eq 0 ]
  [ "$(jq -c '.[] | select(.role == "reviewer") | [.state, .slug, .app_id, .owner]' <<<"$output")" = '["yours","agent-reviewer-tester","7","tester"]' ]
  [ "$(jq -c '.[] | select(.role == "author") | [.state, .name]' <<<"$output")" = '["free","agent-author-tester"]' ]
  [ ! -e "$MANIFESTS.opened" ]
  [ ! -e "$XDG_CONFIG_HOME/dnbg" ]
}

@test "--detect counts an org in --owners as the operator's" {
  github '{"apps":{"agent-reviewer-tester":{"id":7,"owner":"Acme","type":"Organization"}}}'
  bootstrap --detect --roles reviewer --owners=other,acme
  [ "$(jq -c '.[0] | [.state, .owner_type]' <<<"$output")" = '["yours","org"]' ]
  bootstrap --detect --roles reviewer --owners='${user_config.owners}'
  [ "$(jq -r '.[0].state' <<<"$output")" = free ]
}

@test "--detect with no gh login reads every role free, with the reason" {
  github "{$YOURS}"
  BOOTSTRAP_LOGIN='' bootstrap --detect --roles reviewer
  [ "$status" -eq 0 ]
  [ "$(jq -c '.[0] | [.state, .name, (.reason | length > 0)]' <<<"$output")" = '["free","agent-reviewer",true]' ]
}

@test "a create for a role whose bot exists is refused before the browser opens, and --name lifts it" {
  github "{$YOURS}"
  bootstrap --roles reviewer
  [ "$status" -eq 2 ]
  [[ "$output" == *"--adopt reviewer=agent-reviewer-tester"* ]]
  [ ! -e "$MANIFESTS.opened" ]
  bootstrap --roles reviewer --name second-reviewer
  [ "$status" -eq 0 ]
  [ "$(jq -r .slug "$REVIEWER_DIR/config.json")" = second-reviewer ]
}

@test "a key the Downloads watch finds is proven, saved as a create saves, and removed" {
  github "{$YOURS,\"download\":{\"agent-reviewer-tester\":\"KEY-7\"}}"
  bootstrap --roles author --adopt reviewer=agent-reviewer-tester
  [ "$status" -eq 0 ]
  [ "$(cat "$REVIEWER_DIR/private-key.pem")" = KEY-7 ]
  assert_saved "$REVIEWER_DIR"
  [ "$(jq -c '[.app_id, .slug, .bot_login, .owner_type, .owner]' "$REVIEWER_DIR/config.json")" = '["7","agent-reviewer-tester","agent-reviewer-tester[bot]","user","tester"]' ]
  [ "$(jq -cS keys "$REVIEWER_DIR/config.json")" = "$(jq -cS keys "$XDG_CONFIG_HOME/dnbg/author/config.json")" ]
  [ -z "$(ls "$HOME/Downloads")" ]
}

@test "a run connects the roles in --adopt and creates the rest, and says which" {
  github "{$YOURS,\"download\":{\"agent-reviewer-tester\":\"KEY-7\"}}"
  bootstrap --roles author --adopt reviewer=agent-reviewer-tester
  [ "$status" -eq 0 ]
  [ "$(summary | jq -c 'map([.role, .action, .slug])')" = '[["reviewer","connected","agent-reviewer-tester"],["author","created","agent-author-tester"]]' ]
  [ "$(summary | jq -c '.[0] | keys')" = "$(summary | jq -c '.[1] | keys')" ]
  [ "$(wc -l < "$MANIFESTS")" -eq 1 ]
}

@test "--adopt alone creates nothing" {
  github "{$YOURS,\"download\":{\"agent-reviewer-tester\":\"KEY-7\"}}"
  bootstrap --adopt reviewer=agent-reviewer-tester
  [ "$status" -eq 0 ]
  [ ! -s "$MANIFESTS" ]
  [ ! -e "$XDG_CONFIG_HOME/dnbg/author" ]
}

@test "a key from the page's file picker is proven and saved" {
  github "{$YOURS,\"upload\":{\"reviewer\":\"KEY-7\"}}"
  bootstrap --adopt reviewer=agent-reviewer-tester
  [ "$status" -eq 0 ]
  [ "$(cat "$REVIEWER_DIR/private-key.pem")" = KEY-7 ]
  assert_saved "$REVIEWER_DIR"
  [[ "$output" == *"operator's to delete"* ]]
  [[ "$(cat "$MANIFESTS.status")" == *"yours to delete"* ]]
}

@test "a key from --key is proven and saved with no page, and its file left alone" {
  github "{$YOURS}"
  echo KEY-7 > "$BATS_TEST_TMPDIR/mine.pem"
  bootstrap --adopt reviewer=agent-reviewer-tester --key "reviewer=$BATS_TEST_TMPDIR/mine.pem"
  [ "$status" -eq 0 ]
  [ "$(cat "$REVIEWER_DIR/private-key.pem")" = KEY-7 ]
  assert_saved "$REVIEWER_DIR"
  [ -f "$BATS_TEST_TMPDIR/mine.pem" ]
  [[ "$output" == *"operator's to delete"* ]]
  [ ! -e "$MANIFESTS.opened" ]
}

@test "--adopt for a role already set up replaces its key and config" {
  github "{$YOURS}"
  mkdir -p "$REVIEWER_DIR"; echo '{"slug":"existing"}' > "$REVIEWER_DIR/config.json"
  echo KEY-7 > "$BATS_TEST_TMPDIR/mine.pem"
  bootstrap --adopt reviewer=agent-reviewer-tester --key "reviewer=$BATS_TEST_TMPDIR/mine.pem"
  [ "$status" -eq 0 ]
  [ "$(jq -r .slug "$REVIEWER_DIR/config.json")" = agent-reviewer-tester ]
}

@test "the Downloads watch ignores a matching file from before the page was served" {
  github "{$YOURS}"
  old="$HOME/Downloads/agent-reviewer-tester.2026-01-02.private-key.pem"
  echo KEY-7 > "$old"; touch -t 202001010000 "$old"
  bootstrap --adopt reviewer=agent-reviewer-tester --timeout 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"Not connected: reviewer"* ]]
  [ ! -e "$REVIEWER_DIR" ]
  [ -f "$old" ]
}

@test "a key that GET /app answers with another slug is refused, and nothing is written" {
  github '{"apps":{"agent-reviewer-tester":{"id":7,"owner":"tester","hidden":true},"other-app":{"id":9,"owner":"tester"}},
    "keys":{"KEY-9":"other-app"},"upload":{"reviewer":"KEY-9"}}'
  bootstrap --adopt reviewer=agent-reviewer-tester:9 --timeout 2
  [ "$status" -eq 1 ]
  [[ "$(cat "$MANIFESTS.status")" == *"belongs to the App 'other-app', not 'agent-reviewer-tester'"* ]]
  [ ! -e "$REVIEWER_DIR" ]
}

@test "a key GitHub does not accept for the App is refused, and nothing is written" {
  github "{$YOURS}"
  echo KEY-OTHER > "$BATS_TEST_TMPDIR/other.pem"
  bootstrap --roles author --adopt reviewer=agent-reviewer-tester --key "reviewer=$BATS_TEST_TMPDIR/other.pem"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Stopped before: author"* ]]
  [ ! -e "$REVIEWER_DIR" ]
  [ ! -s "$MANIFESTS" ]
}

@test "a slug the lookup cannot see is connected with its App ID, and refused before any page without" {
  github '{"apps":{"agent-reviewer-tester":{"id":7,"owner":"tester","hidden":true}},
    "keys":{"KEY-7":"agent-reviewer-tester"},"upload":{"reviewer":"KEY-7"}}'
  bootstrap --adopt reviewer=agent-reviewer-tester
  [ "$status" -ne 0 ]
  [[ "$output" == *"--adopt reviewer=agent-reviewer-tester:<App ID>"* ]]
  [ ! -e "$MANIFESTS.opened" ]
  bootstrap --adopt reviewer=agent-reviewer-tester:7
  [ "$status" -eq 0 ]
  [ "$(jq -r .app_id "$REVIEWER_DIR/config.json")" = 7 ]
}

@test "a permission shortfall is printed with its consequence, and the credentials are still saved" {
  github '{"apps":{"agent-reviewer-tester":{"id":7,"owner":"tester","permissions":{"pull_requests":"write","issues":"read","metadata":"read"}}},
    "keys":{"KEY-7":"agent-reviewer-tester"}}'
  echo KEY-7 > "$BATS_TEST_TMPDIR/mine.pem"
  bootstrap --adopt reviewer=agent-reviewer-tester --key "reviewer=$BATS_TEST_TMPDIR/mine.pem"
  [ "$status" -eq 0 ]
  [[ "$output" == *"issues: need write, have read"* ]]
  [[ "$output" == *"contents: need write, not granted"*"without it, $(jq -r .consequence.contents "$TREE/roles/reviewer/permissions.json")"* ]]
  [[ "$output" != *"pull_requests: need"* ]]
  [ -f "$REVIEWER_DIR/private-key.pem" ]
}

@test "an over-long default name is shortened the same way on every run, and an over-long --name refused" {
  add_role orchestrator operator
  export BOOTSTRAP_LOGIN=abcdefghijklmn-xyz-and-more
  bootstrap --detect --roles orchestrator
  [ "$(jq -r '.[0].name' <<<"$output")" = agent-orchestrator-abcdefghijklmn ]
  bootstrap --roles orchestrator
  [ "$status" -eq 0 ]
  [ "$(jq -r .name "$MANIFESTS")" = agent-orchestrator-abcdefghijklmn ]
  bootstrap --roles author --name "$(printf 'x%.0s' {1..35})"
  [ "$status" -eq 2 ]
  [[ "$output" == *"GitHub's limit for an App's name is 34"* ]]
  [ "$(wc -l < "$MANIFESTS")" -eq 1 ]
}

@test "where the default name is someone else's App, the first free candidate is the name created" {
  github '{"apps":{"agent-reviewer-tester":{"id":7,"owner":"stranger"}}}'
  bootstrap --detect --roles reviewer
  [ "$(jq -c '.[0] | [.state, .name]' <<<"$output")" = '["free","agent-reviewer-tester-2"]' ]
  bootstrap --roles reviewer
  [ "$status" -eq 0 ]
  [ "$(jq -r .name "$MANIFESTS")" = agent-reviewer-tester-2 ]
}

@test "where the default name is someone else's App and the next candidate is the operator's, the role is yours" {
  github '{"apps":{"agent-reviewer-tester":{"id":7,"owner":"stranger"},"agent-reviewer-tester-2":{"id":8,"owner":"tester"}}}'
  bootstrap --detect --roles reviewer
  [ "$(jq -c '.[0] | [.state, .slug]' <<<"$output")" = '["yours","agent-reviewer-tester-2"]' ]
  bootstrap --roles reviewer
  [ "$status" -eq 2 ]
  [[ "$output" == *"--adopt reviewer=agent-reviewer-tester-2"* ]]
  [ ! -e "$MANIFESTS.opened" ]
}

@test "a suffixed candidate cuts the login further to stay within the limit" {
  run python3 - "$TREE/skills/reviewer-setup" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import bootstrap as b
assert b.default_name("orchestrator", "abcdefghijklmnopqrst") == "agent-orchestrator-abcdefghijklmno"
assert b.default_name("orchestrator", "abcdefghijklmnopqrst", 2) == "agent-orchestrator-abcdefghijklm-2"
assert b.default_name("reviewer", "tester", 3) == "agent-reviewer-tester-3"
assert all(len(b.default_name("orchestrator", "x" * 39, n)) <= b.NAME_LIMIT for n in range(1, 21))
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "the App JWT is signed by the key, RS256, with the App ID as issuer" {
  openssl genrsa -out "$BATS_TEST_TMPDIR/key.pem" 2048 2>/dev/null
  openssl rsa -in "$BATS_TEST_TMPDIR/key.pem" -pubout -out "$BATS_TEST_TMPDIR/pub.pem" 2>/dev/null
  run python3 - "$TREE/skills/reviewer-setup" "$BATS_TEST_TMPDIR" <<'PY'
import base64, json, subprocess, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import bootstrap as b
tmp = Path(sys.argv[2])
decode = lambda part: base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))
header, claims, signature = b.app_jwt("42", (tmp / "key.pem").read_text()).split(".")
assert json.loads(decode(header)) == {"alg": "RS256", "typ": "JWT"}
assert json.loads(decode(claims))["iss"] == "42"
(tmp / "sig").write_bytes(decode(signature))
subprocess.run(["openssl", "dgst", "-sha256", "-verify", str(tmp / "pub.pem"), "-signature",
                str(tmp / "sig")], input=f"{header}.{claims}".encode(), check=True)
try:
    b.app_jwt("42", "not a key")
except b.KeyRefused:
    pass
else:
    raise AssertionError("a file that is no key was signed with")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
