#!/usr/bin/env python3
"""Bootstrap per-developer GitHub Apps for the agent roles.

Creates one App per chosen role (`reviewer`, and any other role defined under
`dnbg-workflow/roles/`), one after another, by driving the GitHub App Manifest
flow end to end except the one browser click GitHub requires to create any App:

  1. Build the role's App manifest from `roles/<role>/permissions.json` (no
     webhook).
  2. Serve a local page that POSTs the manifest to GitHub's create-from-manifest
     URL; you click "Create GitHub App" in the browser.
  3. GitHub redirects back to this server with a temporary code.
  4. Exchange the code via POST /app-manifests/{code}/conversions for the App's
     id, slug, and private key (PEM) — returned exactly once, here.
  5. Save the key (mode 600) and config in the role's own config dir. The key
     never leaves this machine; `as-role.sh` mints short-lived tokens from it.

Stdlib only — no third-party packages.

Example:
  # every role not yet set up, user-owned public Apps:
  python3 bootstrap.py
  # just the reviewer, org-owned private App (needs app-creation rights there):
  python3 bootstrap.py --roles reviewer --owner-type org --org my-org
"""
from __future__ import annotations

import argparse
import html
import json
import os
import re
import secrets
import stat
import subprocess
import sys
import threading
import urllib.error
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

API_ROOT = "https://api.github.com"
ROLES_DIR = Path(__file__).resolve().parent.parent.parent / "roles"


# The names lib-role.sh's role_valid accepts, so setup never creates an App for a
# role the resolver would refuse.
ROLE_NAME = re.compile(r"[a-z][a-z0-9]*(-[a-z0-9]+)*")


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
  ul {{ padding-left: 1.25rem; }}
  li {{ margin: .25rem 0; }}
  code {{ font: .9em ui-monospace, SFMono-Regular, Menlo, monospace; overflow-wrap: anywhere; }}
  .go {{ display: inline-block; font: inherit; font-weight: 600; cursor: pointer;
        padding: .6rem 1.1rem; border: 0; border-radius: 6px; text-decoration: none;
        background: #1f883d; color: #fff; }}
  .note {{ font-size: .875rem; opacity: .7; }}
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


def role_permissions(role: str) -> dict:
    """The role's App permission set, shared with mint-token.sh's runtime audit."""
    return json.loads((ROLES_DIR / role / "permissions.json").read_text())["required"]


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


def save_credentials(config_dir: Path, owner_type: str, org: str, app: dict) -> None:
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
        "owner": org if owner_type == "org" else app.get("owner", {}).get("login", ""),
        "installation_id": "",  # filled after the App is installed (mint-token can also discover it)
        "html_url": app.get("html_url", ""),
    }
    config_path = config_dir / "config.json"
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    config_path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def created_page(installs: list[tuple[str, str]], left: list[str]) -> str:
    """The page shown once a role's App exists. `installs` is (role, install URL)
    for every App this run has created, the newest last; `left` is the roles the
    run still has to create.

    Installing waits for the last page, which carries every App's button: the
    run opens the next role's tab as soon as this one is served, so a button on
    an earlier page would be left behind in a tab nobody is looking at."""
    role = installs[-1][0]
    if left:
        return f"""<h1>&#10003; The {html.escape(role)} bot is created</h1>
<p>This tab is done: you can close it.</p>
<p class="note">The {html.escape(left[0])} bot is next, in a new tab. You install the bots together, after the last is created.</p>"""
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
    buttons = "\n".join(
        f'<p><a class="go" target="_blank" rel="noopener" href="{html.escape(url, quote=True)}">'
        f'Install the {html.escape(r)} bot</a></p>' for r, url in installs)
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
            if parsed.path == "/":
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
                    self._html(400, "<h1>Setup stopped</h1><p>State mismatch — possible CSRF. Setup aborted.</p>")
                    result["error"] = "state mismatch on callback"
                    done.set()
                    return
                code = (qs.get("code") or [""])[0]
                if not code:
                    self._html(400, "<h1>Setup failed</h1><p>No code in callback.</p>")
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
                    self._html(500, f"<h1>Setup failed</h1><p>Manifest conversion failed: {html.escape(str(exc))}</p>")
                    result["error"] = f"manifest conversion failed: {exc}"
                    done.set()
                    return
                # The App now exists on GitHub. If saving its key fails (dir not
                # writable, disk full, chmod fails) the App is orphaned — say so
                # explicitly rather than dying with a traceback in main.
                try:
                    save_credentials(config_dir, owner_type, args.org or "", app)
                except OSError as exc:
                    msg = (f"App '{app.get('slug', '')}' was created on GitHub, but saving its "
                           f"credentials to {config_dir} failed ({exc}). Delete the App in its "
                           f"GitHub settings, fix the directory, and re-run setup.")
                    self._html(500, f"<h1>Setup failed</h1><p>{html.escape(msg)}</p>")
                    result["error"] = msg
                    done.set()
                    return
                result["app"] = app
                install_url = f"https://github.com/apps/{app.get('slug', '')}/installations/new"
                installs = [(e["role"], e["install_url"]) for e in earlier] + [(role, install_url)]
                self._html(200, created_page(installs, left))
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

    app = result["app"]
    slug = app.get("slug", "")
    return {
        "role": role,
        "app_id": str(app["id"]),
        "slug": slug,
        "bot_login": f"{slug}[bot]" if slug else "",
        "config_dir": str(config_dir),
        "install_url": f"https://github.com/apps/{slug}/installations/new",
    }


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


def run(args: argparse.Namespace) -> int:
    if args.name and (not args.roles or len(args.roles.split(",")) != 1):
        print("--name applies to one role; pass --roles <one role>.", file=sys.stderr)
        return 2
    roles = choose_roles(args.roles)
    if not roles:
        print("Every role already has an App set up; name one with --roles to create "
              "another.", file=sys.stderr)
        return 0
    if (args.owner_type or "user") == "org" and not args.org:
        print("--org is required for an org-owned App", file=sys.stderr)
        return 2

    # Every role's, not only the chosen ones': as-role.sh refuses all calls
    # while any role's directory is refused.
    config_dirs = {role: default_config_dir(role) for role in defined_roles()}
    login = gh_login()
    created: list[dict] = []
    status = 0
    for role in roles:
        name = args.name or (f"agent-{role}-{login}" if login else f"agent-{role}")
        left = roles[roles.index(role) + 1:]
        summary = run_flow(args, role, name, config_dirs[role], created, left)
        if summary is None:
            status = 1
            if left:
                print(f"Stopped before: {', '.join(left)}.", file=sys.stderr)
            break
        created.append(summary)
    print(json.dumps(created, indent=2))
    return status


def main() -> int:
    p = argparse.ArgumentParser(description="Bootstrap the agent roles' GitHub Apps.")
    p.add_argument("--roles",
                   help="comma-separated roles to create Apps for (default: every role "
                        "under roles/ with no config.json yet)")
    p.add_argument("--owner-type", choices=["org", "user"], default=None,
                   help="user (default): user-owned public App — installable on the org AND "
                        "your personal account, so it covers both. "
                        "org: org-owned private App — org repos only (no personal repos).")
    p.add_argument("--org", default=None,
                   help="organization login; required only with --owner-type org")
    p.add_argument("--name", help="App name, with one role (default agent-<role>-<your-login>; "
                                  "must be globally unique)")
    p.add_argument("--port", type=int, default=8765, help="localhost callback port")
    p.add_argument("--timeout", type=int, default=600, help="seconds to wait for the browser callback")
    p.add_argument("--no-browser", action="store_true", help="don't auto-open the browser")
    return run(p.parse_args())


if __name__ == "__main__":
    sys.exit(main())
