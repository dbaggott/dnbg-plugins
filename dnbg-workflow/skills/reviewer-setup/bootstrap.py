#!/usr/bin/env python3
"""Bootstrap per-developer GitHub Apps for the agent roles.

Sets up one App per chosen role (`reviewer`, and any other role defined under
`dnbg-workflow/roles/`), one after another. A role with no App gets one
created, by driving the GitHub App Manifest flow end to end except the one
browser click GitHub requires to create any App:

  1. Build the role's App manifest from `roles/<role>/permissions.json` (no
     webhook).
  2. Serve a local page that POSTs the manifest to GitHub's create-from-manifest
     URL; you click "Create GitHub App" in the browser.
  3. GitHub redirects back to this server with a temporary code.
  4. Exchange the code via POST /app-manifests/{code}/conversions for the App's
     id, slug, and private key (PEM) — returned exactly once, here.
  5. Save the key (mode 600) and config in the role's own config dir. The key
     never leaves this machine; `as-role.sh` mints short-lived tokens from it.

A role whose App already exists, created from another machine, is connected
(`--adopt`): GitHub has no API that generates an App private key, so you
generate one in the App's settings, and the downloaded key is proven against the App (`GET /app` under a JWT it signed) before it is saved in
the same files a create writes. `--detect` reports which of the two each role
needs.

Stdlib only — no third-party packages.

Example:
  # which roles have an App of yours already, as JSON; changes nothing:
  python3 bootstrap.py --detect
  # every role not yet set up, user-owned public Apps:
  python3 bootstrap.py
  # just the reviewer, org-owned private App (needs app-creation rights there):
  python3 bootstrap.py --roles reviewer --owner-type org --org my-org
  # connect this machine to the reviewer App another machine created:
  python3 bootstrap.py --adopt reviewer=agent-reviewer-me
"""
from __future__ import annotations

import argparse
import base64
import html
import json
import math
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

API_ROOT = "https://api.github.com"
ROLES_DIR = Path(__file__).resolve().parent.parent.parent / "roles"

# GitHub's limit on the length of an App's name.
NAME_LIMIT = 34
# Where detect_role's walk over candidate names gives up.
CANDIDATE_LIMIT = 20
# In bytes: above any RSA private key's PEM, and below the smallest pipe
# buffer, which app_jwt relies on to hand openssl the key.
PEM_LIMIT = 8192


# The names lib-role.sh's role_valid accepts, so setup never creates an App for a
# role the resolver would refuse.
ROLE_NAME = re.compile(r"[a-z][a-z0-9]*(-[a-z0-9]+)*")
APP_SLUG = re.compile(r"[a-z0-9]+(-[a-z0-9]+)*")


def defined_roles() -> list[str]:
    """Every role with data under roles/, in name order."""
    return sorted(d.name for d in ROLES_DIR.iterdir()
                  if ROLE_NAME.fullmatch(d.name) and (d / "permissions.json").is_file())


def role_env_name(role: str, field: str) -> str:
    return f"DNBG_{role.upper().replace('-', '_')}_{field}"


def role_env(role: str, field: str) -> str:
    return os.environ.get(role_env_name(role, field), "")


def default_config_dir(role: str) -> Path:
    """The role's config dir, read as lib-role.sh's role_config_dir reads it."""
    env = role_env(role, "CONFIG_DIR")
    if not env:
        base = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
        return base / "dnbg" / role
    if env.startswith("~") and env != "~" and not env.startswith("~/"):
        raise SystemExit(f"the {role} role's {role_env_name(role, 'CONFIG_DIR')} is '{env}': "
                         "a ~user path is not supported; use an absolute path, or one "
                         "starting with ~/.")
    return Path(env).expanduser()


def is_configured(role: str) -> bool:
    """What as-role.sh counts as set up: a config.json, or any App variable."""
    return (default_config_dir(role) / "config.json").exists() or any(
        role_env(role, f) for f in ("APP_ID", "PRIVATE_KEY", "PRIVATE_KEY_COMMAND"))


def configured_slug(role: str) -> str:
    """The slug of the App the role is set up with on this machine, if it says."""
    try:
        config = json.loads((default_config_dir(role) / "config.json").read_text())
    except (OSError, ValueError):
        config = {}
    return role_env(role, "SLUG") or str(config.get("slug") or "")


def gh_login() -> str:
    """Current `gh`-authenticated user login, for a unique default App name."""
    try:
        out = subprocess.run(
            ["gh", "api", "user", "--jq", ".login"],
            capture_output=True, text=True, check=True,
        )
        return out.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def default_name(role: str, login: str, n: int = 1) -> str:
    """The role's n-th candidate App name: `agent-<role>-<login>`, then the same
    with `-2`, `-3`, … appended. A login that takes the name past NAME_LIMIT is
    cut to fit, by this rule alone, so every machine computes the name another
    one created the App under."""
    stem = f"agent-{role}"
    tail = "" if n == 1 else f"-{n}"
    room = max(NAME_LIMIT - len(stem) - 1 - len(tail), 0)
    part = login[:room].rstrip("-")
    return f"{stem}-{part}{tail}" if part else stem + tail


def lookup_app(slug: str) -> dict | None:
    """The App at a slug as `gh` sees it, or None on a 404. A 404 is "not found
    this way", not "no such App": a private user-owned App answers 404 even to
    its owner, and a private org-owned one to anyone outside the org."""
    try:
        out = subprocess.run(["gh", "api", f"apps/{slug}"], capture_output=True, text=True)
    except FileNotFoundError:
        raise SystemExit("gh is required to look up an App, and is not installed.")
    if out.returncode != 0:
        if "HTTP 404" in out.stderr:
            return None
        raise SystemExit(f"could not look up the App '{slug}': {out.stderr.strip()}")
    app = json.loads(out.stdout)
    return {"slug": app["slug"], "app_id": str(app["id"]), "owner": owner_login_of(app),
            "owner_type": owner_type_of(app)}


def owner_login_of(app: dict) -> str:
    """The owning account's name, from an App as the API describes it. An
    enterprise, which has no login, is named by its slug."""
    owner = app.get("owner") or {}
    return owner.get("login") or owner.get("slug") or ""


def owner_type_of(app: dict) -> str:
    """`org` or `user`, from an App as the API describes it."""
    return "org" if app.get("owner", {}).get("type") == "Organization" else "user"


def own_accounts(args: argparse.Namespace, login: str) -> set[str]:
    """The accounts whose Apps count as the operator's: the `gh` login, the
    `--owners` list and `--org`, lower-cased."""
    # A `user_config` placeholder still standing is an option nobody has set.
    listed = "" if "${" in (args.owners or "") else (args.owners or "")
    names = [login, args.org or ""] + listed.split(",")
    return {n.strip().lower() for n in names if n.strip()}


def detect_role(role: str, login: str, owners: set[str]) -> dict:
    """Whether the role's App already exists, by walking its candidate names to
    the first that is not someone else's App. The operator's own makes the role
    `yours`, to connect; a 404 makes it `free`, to create under that name."""
    if not login:
        return {"role": role, "state": "free", "name": default_name(role, ""),
                "reason": "no gh login, so nothing could be looked up"}
    for n in range(1, CANDIDATE_LIMIT + 1):
        name = default_name(role, login, n)
        app = lookup_app(name.lower())
        if app is None:
            return {"role": role, "state": "free", "name": name}
        if app["owner"].lower() in owners:
            return {"role": role, "state": "yours", **app}
    raise SystemExit(f"the {role} bot's first {CANDIDATE_LIMIT} default names are all someone "
                     f"else's Apps; pass --name, or --adopt {role}=<slug> for yours.")


# Every page the local server answers with. Self-contained: no script, font or
# image is fetched, so the page renders with no network beyond GitHub itself.
PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>dnbg-workflow setup</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font: 16px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; margin: 0;
         display: grid; place-items: center; min-height: 100vh; padding: 16px;
         box-sizing: border-box; background: Canvas; color: CanvasText; }}
  main {{ max-width: 34rem; }}
  h1 {{ font-size: 1.5rem; margin: 0 0 .5rem; }}
  h2 {{ font-size: 1.1rem; margin: 0 0 .5rem; }}
  ul {{ padding-left: 1.25rem; }}
  li {{ margin: .25rem 0; }}
  code {{ font: .9em ui-monospace, SFMono-Regular, Menlo, monospace; overflow-wrap: anywhere; }}
  .go {{ display: inline-block; font: inherit; font-weight: 600; cursor: pointer;
        padding: .6rem 1.1rem; border: 0; border-radius: 6px; text-decoration: none;
        background: #1f883d; color: #fff; }}
  .note {{ font-size: .875rem; opacity: .7; }}
  .row {{ border-top: 1px solid color-mix(in srgb, CanvasText 20%, transparent);
         padding: 1rem 0 .25rem; }}
  /* A row's steps: the one to do now stands out, the ones done carry a tick and
     recede, and the ones to come stay readable before the first is taken. */
  .steps {{ list-style: none; padding: 0; margin: 0; counter-reset: step; }}
  .steps li {{ counter-increment: step; position: relative; margin: 0;
              padding: .15rem 0 1.1rem 2.75rem; }}
  .steps li::before {{ content: counter(step); position: absolute; left: 0; top: 0;
                      width: 2rem; height: 2rem; border-radius: 50%; box-sizing: border-box;
                      display: grid; place-items: center; font-weight: 700;
                      border: 2px solid currentColor; }}
  .steps li.done {{ opacity: .6; }}
  .saved li.done {{ opacity: 1; }}
  .steps li.now {{ font-weight: 600; }}
  .steps li.now::before {{ background: #1f883d; border-color: #1f883d; color: #fff; }}
  .steps li.done::before {{ content: "\\2713"; border-color: #1f883d; color: #1f883d; }}
  .steps .note {{ display: block; font-weight: 400; margin-top: .35rem; }}
  .saved .steps .pick {{ display: none; }}
  /* The fallback for a redirect that did not happen: hidden while it should. */
  .late {{ visibility: hidden; animation: late 0s 3s forwards; }}
  @keyframes late {{ to {{ visibility: visible; }} }}
</style></head><body><main>
{body}
</main></body></html>"""


def build_manifest(role: str, name: str, redirect_url: str, public: bool) -> dict:
    return {
        "name": name,
        "url": "https://github.com/dbaggott/dnbg-plugins",
        "redirect_url": redirect_url,
        "public": public,
        # No hook_attributes => no webhook. Every role is driven locally, not
        # by GitHub events.
        "default_events": [],
        # `gh pr checks` alone needs three of these, because statusCheckRollup
        # spans check runs, the workflow run each check suite points at, and
        # legacy commit statuses — a missing one fails the whole query, not the
        # node it covers. `actions` was confirmed against a live failure;
        # `statuses` is the one an Actions-only repo never exercises, and is
        # here for repos whose CI posts commit statuses instead of check runs.
        "default_permissions": role_permissions(role),
    }


def role_data(role: str) -> dict:
    return json.loads((ROLES_DIR / role / "permissions.json").read_text())


def role_permissions(role: str) -> dict:
    """The role's App permission set, shared with mint-token.sh's runtime audit."""
    return role_data(role)["required"]


def convert_manifest(code: str) -> dict:
    """Exchange the manifest code for App credentials (no auth — code-gated)."""
    req = urllib.request.Request(
        f"{API_ROOT}/app-manifests/{code}/conversions",
        method="POST",
        data=b"",
        headers={
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Length": "0",
            "User-Agent": "reviewer-setup",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def save_credentials(config_dir: Path, owner_type: str, owner: str, app: dict) -> None:
    """Write a role's key and config. `app` is the App as the API describes it,
    with its private key under `pem`."""
    config_dir.mkdir(parents=True, exist_ok=True)
    # 0700, and chmod rather than mkdir(mode=...): that argument is masked by the
    # umask and is ignored outright when the directory already exists, which is
    # the common case on a re-run. The file modes below are not sufficient on
    # their own — a 0600 PEM inside a group-writable directory can still be
    # REPLACED, and mint-token.sh would sign a JWT with whatever it finds. It
    # refuses such a directory; this is the other half of that contract.
    config_dir.chmod(stat.S_IRWXU)
    pem_path = config_dir / "private-key.pem"
    # Create the key file restricted from the start — no world-readable window.
    # (write_text would create it at 0644-ish and only narrow it after the bytes
    # land.) The App private key is the bot's full credential.
    fd = os.open(pem_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        fh.write(app["pem"])

    slug = app.get("slug", "")
    config = {
        "app_id": str(app["id"]),
        "slug": slug,
        "bot_login": f"{slug}[bot]" if slug else "",
        "owner_type": owner_type,
        "owner": owner,
        "installation_id": "",  # filled after the App is installed (mint-token can also discover it)
        "html_url": app.get("html_url", ""),
    }
    config_path = config_dir / "config.json"
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    config_path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def role_summary(role: str, app: dict, config_dir: Path, action: str) -> dict:
    """A role's entry in the run's JSON output; `action` is `created` or `connected`."""
    slug = app.get("slug", "")
    return {
        "role": role,
        "action": action,
        "app_id": str(app["id"]),
        "slug": slug,
        "bot_login": f"{slug}[bot]" if slug else "",
        "config_dir": str(config_dir),
        "install_url": f"https://github.com/apps/{slug}/installations/new",
    }


class KeyRefused(Exception):
    """A key that was not saved. The message is worded for the operator."""


class KeyUnchecked(KeyRefused):
    """A key GitHub gave no verdict on, so offering it again may succeed."""


def app_jwt(app_id: str, pem: str) -> str:
    """An App JWT signed with the key, as mint-token.sh signs one."""
    def b64url(raw: bytes) -> str:
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

    key = pem.encode()
    if len(key) > PEM_LIMIT:
        raise KeyRefused("That file is too large to be an App private key.")
    now = int(time.time())
    claims = {"iat": now - 60, "exp": now + 540, "iss": app_id}
    unsigned = (b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode()) + "."
                + b64url(json.dumps(claims).encode()))
    # The key reaches openssl through a pipe: it is not yet proven, so it is not
    # yet written anywhere.
    key_out, key_in = os.pipe()
    try:
        try:
            os.write(key_in, key)
        finally:
            os.close(key_in)
        signed = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", f"/dev/fd/{key_out}", "-binary"],
            input=unsigned.encode(), capture_output=True, pass_fds=(key_out,))
    except OSError as exc:
        raise KeyUnchecked(f"The key could not be handed to openssl ({exc}).")
    finally:
        os.close(key_out)
    if signed.returncode != 0 or not signed.stdout:
        raise KeyRefused("That file is not a usable RSA private key.")
    return f"{unsigned}.{b64url(signed.stdout)}"


def prove_key(app_id: str, pem: str) -> dict:
    """The App the key belongs to, as `GET /app` answers under a JWT it signed."""
    req = urllib.request.Request(
        f"{API_ROOT}/app",
        headers={
            "Authorization": f"Bearer {app_jwt(app_id, pem)}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "reviewer-setup",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        # 401 where the ID is another App's, 404 where it is no App's.
        if exc.code in (401, 404):
            raise KeyRefused(f"GitHub did not accept that key for the App with ID {app_id}: "
                             "it was generated for another App, or has since been deleted.")
        raise KeyUnchecked(f"GitHub answered HTTP {exc.code} when the key was checked.")
    except (OSError, ValueError) as exc:
        raise KeyUnchecked(f"GitHub could not be asked about the key ({exc}).")


def permission_shortfall(role: str, granted: dict) -> str:
    """Each permission the role needs that the App lacks, with its consequence,
    in mint-token.sh's wording; empty when none."""
    spec = role_data(role)
    rank = {"read": 1, "write": 2, "admin": 3}
    lines = []
    for perm, need in spec["required"].items():
        have = granted.get(perm)
        if rank.get(have, 0) < rank.get(need, 0):
            lines.append(f"  {perm}: need {need}, " + (f"have {have}" if have else "not granted")
                         + f"\n      without it, "
                         + spec.get("consequence", {}).get(perm, "a capability is lost"))
    return "\n".join(lines)


def connect(target: dict, pem: str) -> dict:
    """Prove a key against the App a role is being connected to, then save it as
    a create would. Returns the role's summary. Raises KeyRefused, with nothing
    written, for a key that is not that App's."""
    role, slug = target["role"], target["slug"]
    app = prove_key(target["app_id"], pem)
    if app.get("slug") != slug:
        raise KeyRefused(f"That key belongs to the App '{app.get('slug', '')}', not '{slug}'.")
    shortfall = permission_shortfall(role, app.get("permissions") or {})
    if shortfall:
        print(f"The {role} App '{slug}' requests less than the role needs:\n\n{shortfall}\n\n"
              "  Its key is saved all the same. This is what the App requests, not what each\n"
              "  installation has accepted, which Verify and the first mint show. The fix is\n"
              "  \"Repair / rotate\", \"A permission is missing\", in reviewer-setup's SKILL.md.",
              file=sys.stderr)
    try:
        save_credentials(target["config_dir"], owner_type_of(app), owner_login_of(app),
                         {**app, "pem": pem})
    except OSError as exc:
        raise KeyRefused(f"The key is the right one, but saving it to {target['config_dir']} "
                         f"failed ({exc}).")
    return role_summary(role, app, target["config_dir"], "connected")


def downloads_dir() -> Path:
    return Path.home() / "Downloads"


def downloaded_keys(slug: str, since: float) -> list[tuple[Path, float]]:
    """The private keys a browser saved for this App since `since`, oldest
    first, each with its modification time. GitHub names the download
    `<slug>.<date>.private-key.pem`, and a browser adds ` (1)` and the like to a
    name already taken. The date is not compared: an older key for the same App
    has the same shape of name, and a key generated near midnight may carry
    either day."""
    name = re.compile(re.escape(slug) + r"\.\d{4}-\d{2}-\d{2}\.private-key.*\.pem")
    found = []
    try:
        for path in downloads_dir().iterdir():
            if name.fullmatch(path.name):
                modified = path.stat().st_mtime
                # Floored, for a filesystem that keeps whole seconds.
                if modified >= math.floor(since):
                    found.append((path, modified))
    except OSError:
        return []
    return sorted(found, key=lambda entry: entry[1])


CONNECT_SCRIPT = """
// Which step of its row each role is at: 1 before its settings were opened from
// here, 2 once they were, 3 once a key was offered, 4 once one is saved.
const opened = new Set();
function show(row) {
  const step = row.state === 'saved' ? 4 : row.state === 'refused' ? 3
    : opened.has(row.role) ? 2 : 1;
  document.querySelectorAll('#row-' + row.role + ' li').forEach((li, i) => {
    li.className = i + 1 < step ? 'done' : i + 1 === step ? 'now' : '';
  });
  document.getElementById('row-' + row.role).classList.toggle('saved', step === 4);
  document.getElementById('status-' + row.role).textContent = row.text;
}
let rows = [];
function render(status) {
  rows = status.rows;
  rows.forEach(show);
  document.getElementById('end').textContent = status.end;
  return status.done;
}
async function poll() {
  let status;
  try { status = await (await fetch('/status')).json(); } catch (e) { return; }
  if (!render(status)) setTimeout(poll, 1000);
}
for (const link of document.querySelectorAll('a[data-role]')) {
  link.addEventListener('click', () => { opened.add(link.dataset.role); rows.forEach(show); });
}
for (const input of document.querySelectorAll('input[type=file]')) {
  input.addEventListener('change', async () => {
    if (!input.files.length) return;
    const answer = await fetch('/key/' + input.dataset.role + '?state=' + STATE,
                               {method: 'POST', body: await input.files[0].text()});
    input.value = '';
    if (answer.ok) render(await answer.json());
    else document.getElementById('status-' + input.dataset.role).textContent =
      'That file was not taken: it is empty, or too large to be a private key.';
  });
}
poll();
"""

SAVED = "Found, verified and saved."


def connect_page(targets: list[dict], state: str, watching: bool) -> str:
    """The page for the roles being connected: a row each, laid out as the three
    steps the operator takes, which the page's script marks as they are done."""
    def row(t: dict) -> str:
        role = html.escape(t["role"], quote=True)
        return f"""<section class="row" id="row-{role}">
<h2>The {role} bot: <code>{html.escape(t["slug"])}</code></h2>
<ol class="steps">
<li class="now"><a class="go" target="_blank" rel="noopener" data-role="{role}" href="{html.escape(t["settings_url"], quote=True)}">Open its settings on GitHub</a></li>
<li>On GitHub, find the App's <b>credentials</b> and generate a new <b>private key</b>.
<span class="note">A private key, <b>not</b> a client secret. A <code>.pem</code> file downloads.</span></li>
<li><span id="status-{role}">{html.escape(waiting_text(watching))}</span>
<span class="note pick">{"Download not picked up? Choose the file:" if watching else "Choose the downloaded file:"}
<input type="file" accept=".pem" data-role="{role}"></span></li>
</ol>
</section>"""

    one = len(targets) == 1
    return f"""<h1>Connect this machine to your {"bot" if one else "bots"}</h1>
<p>{"This bot already exists" if one else "These bots already exist"} on GitHub. This machine needs a private key of its own for {"it" if one else "each"}: three steps{"" if one else " per bot"}, the second of them on GitHub.</p>
{chr(10).join(row(t) for t in targets)}
<p id="end"></p>
<noscript><p>This page needs JavaScript to show progress and to take a chosen file.</p></noscript>
<script>const STATE = {json.dumps(state)};{CONNECT_SCRIPT}</script>"""


def waiting_text(watching: bool) -> str:
    """A row's third step while no key has been saved for it."""
    if watching:
        return "Come back to this tab. It picks the key up from your Downloads folder."
    return ("Come back to this tab and choose the downloaded file. This terminal cannot "
            "read your Downloads folder.")


def run_connect(args: argparse.Namespace, targets: list[dict], next_role: str | None) -> dict:
    """Serve the connect page until every target's key is proven and saved, or
    the timeout. Returns the summaries of the roles saved, by role. `next_role`
    is the first role the run creates afterwards, if any."""
    # Guards the key upload as run_flow's guards its callback: only a page this
    # server served can post one.
    state = secrets.token_urlsafe(24)
    try:
        os.listdir(downloads_dir())
        watching = True
    except OSError:
        watching = False
    rows = {t["role"]: {"target": t, "state": "waiting", "text": waiting_text(watching)}
            for t in targets}
    saved: dict[str, dict] = {}
    lock = threading.Lock()
    all_saved = threading.Event()
    final_status_served = threading.Event()
    stop_watching = threading.Event()
    flow: dict = {"tabs": not args.no_browser, "served_at": None}

    def offer(role: str, pem: str, download: Path | None = None) -> bool:
        """Whether GitHub gave a verdict on the key, saved or refused."""
        with lock:
            if role in saved:
                return True
            try:
                saved[role] = connect(rows[role]["target"], pem)
            except KeyRefused as exc:
                rows[role].update(state="refused",
                                  text=f"{exc} Still waiting for this bot's key.")
                return not isinstance(exc, KeyUnchecked)
            rows[role]["state"] = "saved"
            if download is None:
                rows[role]["text"] = f"{SAVED} The file you chose is still where it was, and is yours to delete."
                print(f"The {role} bot's key came from a file chosen in the browser; that copy "
                      "is the operator's to delete.", file=sys.stderr)
            else:
                try:
                    download.unlink()
                    rows[role]["text"] = f"{SAVED} The download is removed from your Downloads folder."
                except OSError:
                    rows[role]["text"] = f"{SAVED} The download could not be removed, and is yours to delete."
                    print(f"{download} could not be removed; it is the operator's to delete.",
                          file=sys.stderr)
            if len(saved) == len(rows):
                all_saved.set()
            return True

    def watch() -> None:
        refused: set[tuple[Path, float]] = set()
        retry_at: dict[Path, float] = {}
        while not stop_watching.wait(0.5):
            since = flow["served_at"]
            if since is None:
                continue
            for role, row in rows.items():
                for path, modified in downloaded_keys(row["target"]["slug"], since):
                    if (role in saved or (path, modified) in refused
                            or time.monotonic() < retry_at.get(path, 0)):
                        continue
                    try:
                        pem = path.read_text()
                    except (OSError, UnicodeDecodeError):
                        continue
                    if not pem.strip():
                        continue
                    if offer(role, pem, path):
                        refused.add((path, modified))
                    else:
                        retry_at[path] = time.monotonic() + 5

    def status() -> dict:
        done = all_saved.is_set()
        if not done:
            end = ""
        elif next_role is None:
            end = "All connected. Close this tab and return to Claude Code."
        elif flow["tabs"]:
            end = f"All connected. The {next_role} bot is created next, in a new tab."
        else:
            end = f"All connected. Reload this page to create the {next_role} bot."
        return {"rows": [{"role": r, "state": row["state"], "text": row["text"]}
                         for r, row in rows.items()],
                "done": done, "end": end}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):  # quiet
            pass

        def _send(self, code: int, content_type: str, body: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.end_headers()
            self.wfile.write(body.encode())

        def do_GET(self):  # noqa: N802
            path = urlparse(self.path).path
            if path == "/":
                if flow["served_at"] is None:
                    flow["served_at"] = time.time()
                self._send(200, "text/html; charset=utf-8",
                           PAGE.format(body=connect_page(targets, state, watching)))
            elif path == "/status":
                answer = status()
                self._send(200, "application/json", json.dumps(answer))
                if answer["done"]:
                    final_status_served.set()
            else:
                self._send(404, "text/html; charset=utf-8", PAGE.format(body="not found"))

        def do_POST(self):  # noqa: N802
            parsed = urlparse(self.path)
            role = parsed.path.removeprefix("/key/")
            try:
                length = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                length = 0
            if ((parse_qs(parsed.query).get("state") or [""])[0] != state
                    or role not in rows or not 0 < length <= PEM_LIMIT):
                self._send(400, "application/json", "{}")
                return
            offer(role, self.rfile.read(length).decode(errors="replace"))
            self._send(200, "application/json", json.dumps(status()))

    try:
        server = HTTPServer(("localhost", args.port), Handler)
    except OSError as exc:
        print(f"Could not bind localhost:{args.port} ({exc}) — it may be in use by a "
              f"previous run. Retry with --port <other>.", file=sys.stderr)
        return saved
    threading.Thread(target=server.serve_forever, daemon=True).start()
    threading.Thread(target=watch, daemon=True).start()

    open_url = f"http://localhost:{args.port}/"
    names = ", ".join(rows)
    print(f"Opening {open_url} — generate a private key for {names} in your browser.",
          file=sys.stderr)
    if not args.no_browser and not webbrowser.open(open_url):
        flow["tabs"] = False
        print(f"No browser could be opened here. Open {open_url} yourself, on this machine.",
              file=sys.stderr)

    if all_saved.wait(timeout=args.timeout):
        # The page learns a row's state by polling, so the server stays up for
        # the poll that shows the last row saved.
        final_status_served.wait(timeout=3)
    else:
        print(f"Timed out after {args.timeout}s waiting for a private key.", file=sys.stderr)
    stop_watching.set()
    server.shutdown()
    # Released here, so a create flow that follows can bind the same port.
    server.server_close()
    return saved


def install_buttons(installs: list[tuple[str, str]]) -> str:
    return "\n".join(
        f'<p><a class="go" target="_blank" rel="noopener" href="{html.escape(url, quote=True)}">'
        f'Install the {html.escape(r)} bot</a></p>' for r, url in installs)


def failed_page(heading: str, detail: str, installs: list[tuple[str, str]]) -> str:
    """A page for a role whose App was not set up. The Apps the run created
    before it get their install buttons here, since its last page never comes."""
    body = f"<h1>{heading}</h1><p>{html.escape(detail)}</p>"
    if installs:
        body += ("<p>The bots created before this one still need installing. "
                 "Each button opens GitHub in a new tab.</p>" + install_buttons(installs))
    return body


def created_page(installs: list[tuple[str, str]], left: list[str], tabs: bool = True) -> str:
    """The page shown once a role's App exists. `installs` is (role, install URL)
    for every App this run has created, the newest last; `left` is the roles the
    run still has to create; `tabs` is whether the run opens each role's page
    itself.

    Installing waits for the last page, which carries every App's button: the
    run opens the next role's tab as soon as this one is served, so a button on
    an earlier page would be left behind in a tab nobody is looking at."""
    role = installs[-1][0]
    if left and tabs:
        return f"""<h1>&#10003; The {html.escape(role)} bot is created</h1>
<p>This tab is done: you can close it.</p>
<p class="note">The {html.escape(left[0])} bot is next, in a new tab. You install the bots together, after the last is created.</p>"""
    if left:
        # No browser was opened for this run, so none will be for the next role.
        return f"""<h1>&#10003; The {html.escape(role)} bot is created</h1>
<p><a class="go" href="/start/{html.escape(left[0], quote=True)}">Next: the {html.escape(left[0])} bot</a></p>
<p class="note">You install the bots together, after the last is created.</p>"""
    if len(installs) == 1:
        heading = f"The {html.escape(role)} bot is created"
        step = "One step left: install it."
        how = "The button opens GitHub in a new tab."
        closing = "When it is installed, close this tab and return to Claude Code."
    else:
        heading = f"All {len(installs)} bots are created"
        step = "One step left: install each of them."
        how = "Each button opens GitHub in a new tab. Come back here after each one."
        closing = "When all are installed, close this tab and return to Claude Code."
    buttons = install_buttons(installs)
    return f"""<h1>&#10003; {heading}</h1>
<p>{step} GitHub will ask which repos:</p>
<ul>
<li><b>All repositories</b> (recommended): least upkeep; new repos are covered automatically.</li>
<li><b>Only select repositories</b>: limits what the bot can touch; you add new repos later.</li>
</ul>
<p class="note">You can change this at any time on GitHub, under Settings, then Applications.</p>
<p>{how}</p>
{buttons}
<p class="note">{closing}</p>"""


def run_flow(args: argparse.Namespace, role: str, name: str, config_dir: Path,
             earlier: list[dict], left: list[str]) -> dict | None:
    """Create one role's App. Returns its summary, or None after printing why not.
    `earlier` is the summaries of the Apps this run already created, and `left`
    the roles it creates after this one."""
    # Default to user-owned + public: the only model installable on BOTH the org
    # (for org PRs) and your personal account (for personal repos). Private Apps
    # install only on their owner, so --owner-type org covers org repos only.
    owner_type = args.owner_type or "user"
    public = owner_type == "user"

    # CSRF guard: GitHub echoes this back on the /callback redirect, so the
    # callback handler only accepts a code that came from the page we served.
    state = secrets.token_urlsafe(24)
    if owner_type == "org":
        create_url = f"https://github.com/organizations/{args.org}/settings/apps/new?state={state}"
    else:
        create_url = f"https://github.com/settings/apps/new?state={state}"

    result: dict = {}
    done = threading.Event()
    before = [(e["role"], e["install_url"]) for e in earlier]
    # Whether this run opens each role's page itself; settled below, before any
    # callback can be served.
    flow = {"tabs": not args.no_browser}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):  # quiet
            pass

        def _html(self, code: int, body: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(PAGE.format(body=body).encode())

        def do_GET(self):  # noqa: N802
            parsed = urlparse(self.path)
            # `/start/<role>` is the link an earlier role's page carries when no
            # browser is opened: only this role's server answers it, so a click
            # that lands before the hand-over cannot start the earlier role again.
            if parsed.path in ("/", f"/start/{role}"):
                manifest = build_manifest(role, name, f"http://localhost:{args.port}/callback", public)
                # Auto-submitting form: the manifest must be POSTed to GitHub.
                # html.escape so the embedded JSON is safe in the attribute
                # regardless of manifest content (defense-in-depth).
                manifest_attr = html.escape(json.dumps(manifest), quote=True)
                self._html(200, f"""<form id="f" action="{html.escape(create_url, quote=True)}" method="post">
  <input type="hidden" name="manifest" value="{manifest_attr}">
</form>
<p>Taking you to GitHub to create the {html.escape(role)} bot&hellip;</p>
<div class="late">
<p class="note">Still here? Continue by hand:</p>
<p><button class="go" form="f" type="submit">Continue to GitHub</button></p>
</div>
<script>document.getElementById('f').submit();</script>""")
            elif parsed.path == "/callback":
                qs = parse_qs(parsed.query)
                if (qs.get("state") or [""])[0] != state:
                    self._html(400, failed_page("Setup stopped", "State mismatch — possible CSRF. Setup aborted.", before))
                    result["error"] = "state mismatch on callback"
                    done.set()
                    return
                code = (qs.get("code") or [""])[0]
                if not code:
                    self._html(400, failed_page("Setup failed", "No code in callback.", before))
                    result["error"] = "no code in callback"
                    done.set()
                    return
                try:
                    app = convert_manifest(code)
                    # Validate here (not in save_credentials) so a malformed 200
                    # response fails fast with an accurate message instead of
                    # raising KeyError out of the save step and hanging main.
                    if not all(k in app for k in ("id", "pem", "slug")):
                        raise KeyError("conversion response missing id/pem/slug")
                except (urllib.error.HTTPError, urllib.error.URLError, KeyError) as exc:
                    self._html(500, failed_page("Setup failed", f"Manifest conversion failed: {exc}", before))
                    result["error"] = f"manifest conversion failed: {exc}"
                    done.set()
                    return
                # The App now exists on GitHub. If saving its key fails (dir not
                # writable, disk full, chmod fails) the App is orphaned — say so
                # explicitly rather than dying with a traceback in main.
                try:
                    owner = ((args.org or "") if owner_type == "org"
                             else app.get("owner", {}).get("login", ""))
                    save_credentials(config_dir, owner_type, owner, app)
                except OSError as exc:
                    msg = (f"App '{app.get('slug', '')}' was created on GitHub, but saving its "
                           f"credentials to {config_dir} failed ({exc}). Delete the App in its "
                           f"GitHub settings, fix the directory, and re-run setup.")
                    self._html(500, failed_page("Setup failed", msg, before))
                    result["error"] = msg
                    done.set()
                    return
                result["app"] = app
                install_url = f"https://github.com/apps/{app.get('slug', '')}/installations/new"
                self._html(200, created_page(before + [(role, install_url)], left, flow["tabs"]))
                done.set()
            else:
                self._html(404, "not found")

    try:
        server = HTTPServer(("localhost", args.port), Handler)
    except OSError as exc:
        print(f"Could not bind localhost:{args.port} ({exc}) — it may be in use by a "
              f"previous run. Retry with --port <other>.", file=sys.stderr)
        return None
    threading.Thread(target=server.serve_forever, daemon=True).start()

    open_url = f"http://localhost:{args.port}/"
    print(f"Opening {open_url} — complete the {role} App's creation in your browser.", file=sys.stderr)
    if not args.no_browser and not webbrowser.open(open_url):
        flow["tabs"] = False
        print(f"No browser could be opened here. Open {open_url} yourself, on this machine.",
              file=sys.stderr)

    if not done.wait(timeout=args.timeout):
        print(f"Timed out after {args.timeout}s waiting for the GitHub callback.", file=sys.stderr)
        server.shutdown()
        server.server_close()
        return None
    server.shutdown()
    # Released here, so the next role's flow can bind the same port.
    server.server_close()

    if "error" in result or "app" not in result:
        print(f"Setup failed for {role}: {result.get('error', 'unknown error')}", file=sys.stderr)
        return None

    return role_summary(role, result["app"], config_dir, "created")


def choose_roles(requested: str | None) -> list[str]:
    """The named roles, or by default every defined role with no config yet."""
    known = defined_roles()
    if requested:
        roles = [r.strip() for r in requested.split(",") if r.strip()]
        unknown = [r for r in roles if r not in known]
        if unknown:
            raise SystemExit(f"unknown role(s) {', '.join(unknown)}; defined: {', '.join(known)}")
        return roles
    return [r for r in known if not is_configured(r)]


def role_pairs(flag: str, values: list[str] | None) -> dict[str, str]:
    """A repeatable `<role>=<value>` flag as a dict, refusing a role not defined."""
    known = defined_roles()
    pairs: dict[str, str] = {}
    for value in values or []:
        role, eq, rest = value.partition("=")
        if not eq or not rest:
            raise SystemExit(f"{flag} takes <role>=<value>; got '{value}'.")
        if role not in known:
            raise SystemExit(f"unknown role(s) {role}; defined: {', '.join(known)}")
        pairs[role] = rest
    return pairs


def adopt_target(role: str, value: str, config_dir: Path) -> dict:
    """The App a role is to be connected to, from `--adopt`'s `<slug>[:<app id>]`."""
    slug, _, app_id = value.partition(":")
    slug = slug.lower()
    if not APP_SLUG.fullmatch(slug) or (app_id and not app_id.isdigit()):
        raise SystemExit(f"--adopt {role}={value}: expected <slug> or <slug>:<App ID>, the slug "
                         "being the last part of the App's settings URL.")
    app = lookup_app(slug)
    if app is None:
        if not app_id:
            raise SystemExit(
                f"the App '{slug}' cannot be looked up, which is how GitHub answers for a "
                f"private App under a personal account, and for a slug that names none. For "
                f"the first, pass --adopt {role}={slug}:<App ID>, the App ID being on the "
                "App's settings page.")
        # Only a private user-owned App is hidden from its own owner, so its
        # settings are at the user form of the URL.
        app = {"slug": slug, "app_id": app_id, "owner": "", "owner_type": "user"}
    if app["owner_type"] == "org":
        settings_url = f"https://github.com/organizations/{app['owner']}/settings/apps/{slug}"
    else:
        settings_url = f"https://github.com/settings/apps/{slug}"
    return {"role": role, "config_dir": config_dir, "settings_url": settings_url, **app}


def run(args: argparse.Namespace) -> int:
    if args.detect:
        login = gh_login()
        owners = own_accounts(args, login)
        print(json.dumps([detect_role(r, login, owners) for r in choose_roles(args.roles)],
                         indent=2))
        return 0

    if args.name and (not args.roles or len(args.roles.split(",")) != 1):
        print("--name applies to one role; pass --roles <one role>.", file=sys.stderr)
        return 2
    if args.name and len(args.name) > NAME_LIMIT:
        print(f"--name is {len(args.name)} characters; GitHub's limit for an App's name is "
              f"{NAME_LIMIT}.", file=sys.stderr)
        return 2
    adopt = role_pairs("--adopt", args.adopt)
    key_paths = role_pairs("--key", args.key)
    unadopted = [r for r in key_paths if r not in adopt]
    if unadopted:
        print(f"--key applies to a role named in --adopt; {', '.join(unadopted)} is not.",
              file=sys.stderr)
        return 2
    # With --adopt alone, the run is the roles it names; --roles adds roles to create.
    roles = choose_roles(args.roles) if args.roles or not adopt else []
    creates = [r for r in roles if r not in adopt]
    if args.name and not creates:
        print("--name is for a role being created; the role named is in --adopt.",
              file=sys.stderr)
        return 2
    for role in adopt:
        elsewhere = [role_env_name(role, f) for f in ("APP_ID", "PRIVATE_KEY", "PRIVATE_KEY_COMMAND")
                     if role_env(role, f)]
        if elsewhere:
            print(f"The {role} role takes its App from {', '.join(elsewhere)}, ahead of the "
                  "files --adopt writes, so a key saved here would not be the one used. Unset "
                  "it, or put the new key where that setting reads it.", file=sys.stderr)
            return 2
    if adopt and not shutil.which("openssl"):
        print("openssl is required to check a private key, and is not installed.",
              file=sys.stderr)
        return 2
    if not creates and not adopt:
        print("Every role is already set up on this machine. To give it a new key for a "
              "role's App, pass --adopt <role>=<slug>.", file=sys.stderr)
        return 0
    if creates and (args.owner_type or "user") == "org" and not args.org:
        print("--org is required for an org-owned App", file=sys.stderr)
        return 2

    # Every role's, not only the chosen ones': as-role.sh refuses all calls
    # while any role's directory is refused.
    config_dirs = {role: default_config_dir(role) for role in defined_roles()}

    # Everything that can refuse the run is settled here, before a page opens.
    targets = [adopt_target(role, value, config_dirs[role]) for role, value in adopt.items()]
    slugs = [t["slug"] for t in targets]
    if len(set(slugs)) != len(slugs):
        print("--adopt names one App for two roles; each role needs its own.", file=sys.stderr)
        return 2
    keys: dict[str, str] = {}
    for role, path in key_paths.items():
        try:
            keys[role] = Path(path).expanduser().read_text()
        except (OSError, UnicodeDecodeError) as exc:
            print(f"--key {role}={path}: could not be read ({exc}).", file=sys.stderr)
            return 2
    names: dict[str, str] = {}
    if creates:
        login = gh_login()
        owners = own_accounts(args, login)
        if not login and not args.name:
            print("No gh login, so whether a bot of yours already exists could not be "
                  "checked.", file=sys.stderr)
        for role in creates:
            if args.name:
                names[role] = args.name
                continue
            if is_configured(role):
                slug = configured_slug(role) or "<slug>"
                print(f"The {role} role is already set up on this machine. To give it a new "
                      f"key for the same App, pass --adopt {role}={slug}; to create a second "
                      "App in its place, pass --name.", file=sys.stderr)
                return 2
            found = detect_role(role, login, owners)
            if found["state"] == "yours":
                print(f"Your {role} bot already exists: '{found['slug']}'. Connect this machine "
                      f"to it with --adopt {role}={found['slug']}, or pass --name to create a "
                      "second App.", file=sys.stderr)
                return 2
            names[role] = found["name"]
            if len(names[role]) > NAME_LIMIT:
                print(f"No default name for the {role} bot fits GitHub's {NAME_LIMIT} "
                      "characters; pass --name.", file=sys.stderr)
                return 2
            if login and names[role] != f"agent-{role}-{login}":
                print(f"The {role} bot is created as '{names[role]}': the default, "
                      f"agent-{role}-{login}, is over GitHub's {NAME_LIMIT} characters or is "
                      "someone else's App.", file=sys.stderr)

    done: list[dict] = []

    def stop(failed: str | None = None) -> int:
        reached = {summary["role"] for summary in done} | {failed}
        unreached = [r for r in list(adopt) + creates if r not in reached]
        if unreached:
            print(f"Stopped before: {', '.join(unreached)}.", file=sys.stderr)
        print(json.dumps(done, indent=2))
        return 1

    for target in targets:
        role = target["role"]
        if role not in keys:
            continue
        try:
            done.append(connect(target, keys[role]))
        except KeyRefused as exc:
            print(f"--key {role}={key_paths[role]}: {exc}", file=sys.stderr)
            return stop(role)
        print(f"{key_paths[role]} is saved as the {role} bot's key; that copy is the "
              "operator's to delete.", file=sys.stderr)
    on_page = [t for t in targets if t["role"] not in keys]
    if on_page:
        saved = run_connect(args, on_page, creates[0] if creates else None)
        done.extend(saved.values())
        missed = [t["role"] for t in on_page if t["role"] not in saved]
        if missed:
            print(f"Not connected: {', '.join(missed)}.", file=sys.stderr)
            return stop()

    created: list[dict] = []
    for role in creates:
        left = creates[creates.index(role) + 1:]
        summary = run_flow(args, role, names[role], config_dirs[role], created, left)
        if summary is None:
            return stop(role)
        created.append(summary)
        done.append(summary)
    print(json.dumps(done, indent=2))
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Bootstrap the agent roles' GitHub Apps.")
    p.add_argument("--roles",
                   help="comma-separated roles to create Apps for (default: every role "
                        "under roles/ with no config.json yet, or none with --adopt)")
    p.add_argument("--detect", action="store_true",
                   help="print as JSON, for each of those roles, whether an App of yours "
                        "already exists (yours) or one would be created (free); writes "
                        "nothing and opens no browser")
    p.add_argument("--owners", default="",
                   help="comma-separated accounts whose Apps count as yours, beside your "
                        "gh login")
    p.add_argument("--adopt", action="append", metavar="ROLE=SLUG[:APP_ID]",
                   help="connect this machine to a role's existing App with a new private "
                        "key, in place of creating one; repeatable. The App ID is needed "
                        "only for an App that cannot be looked up")
    p.add_argument("--key", action="append", metavar="ROLE=PATH",
                   help="with --adopt, take that role's private key from a file; repeatable")
    p.add_argument("--owner-type", choices=["org", "user"], default=None,
                   help="user (default): user-owned public App — installable on the org AND "
                        "your personal account, so it covers both. "
                        "org: org-owned private App — org repos only (no personal repos).")
    p.add_argument("--org", default=None,
                   help="organization login; required only with --owner-type org")
    p.add_argument("--name", help="App name, with one role (default agent-<role>-<your-login>; "
                                  f"must be globally unique, and at most {NAME_LIMIT} "
                                  "characters)")
    p.add_argument("--port", type=int, default=8765, help="localhost callback port")
    p.add_argument("--timeout", type=int, default=600, help="seconds to wait for the browser")
    p.add_argument("--no-browser", action="store_true", help="don't auto-open the browser")
    return run(p.parse_args())


if __name__ == "__main__":
    sys.exit(main())
