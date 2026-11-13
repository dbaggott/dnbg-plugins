"""Run bootstrap.py's main() with GitHub replaced and the browser click driven.

  python3 drive.py <bootstrap-dir> <manifest-log> [bootstrap args…]

Each "browser open" touches <manifest-log>.opened and fetches the local page.
On a create page it records the manifest the page would POST and follows
GitHub's redirect back with the page's own state; the conversion answers as
GitHub would, with an App named after the manifest. On the connect page it does
what the world file says, then polls the page's status until the run is done,
leaving the last answer in <manifest-log>.status.

$BOOTSTRAP_GITHUB names the world file, JSON standing in for GitHub and for the
operator's clicks. Unset, GitHub has no Apps.

  apps      {slug: {id, owner, type?, permissions?, hidden?}}; `type` is
            `User` unless given, and a `hidden` App answers the lookup with 404
  keys      {pem text: slug}, the App each key signs for
  download  {slug: pem text}, keys the click saves to ~/Downloads, each named
            as a browser names the day's second download
  upload    {role: pem text}, keys the click sends through the file picker

$BOOTSTRAP_LOGIN is the `gh` login, `tester` unless set.
"""
import json
import os
import re
import sys
import threading
import time
import urllib.request
from html import unescape
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import bootstrap  # noqa: E402

LOG = sys.argv[2]
WORLD = json.loads(Path(os.environ["BOOTSTRAP_GITHUB"]).read_text()) if os.environ.get("BOOTSTRAP_GITHUB") else {}
APPS = WORLD.get("apps", {})
ALL_PERMISSIONS = {"pull_requests": "write", "issues": "write", "contents": "write",
                   "checks": "read", "actions": "read", "statuses": "read", "metadata": "read"}
seen = {}


def owner_of(app):
    return {"login": app["owner"], "type": app.get("type", "User")}


def create(url, page, manifest_attr):
    state = re.search(r"state=([^\"&]+)", page).group(1)
    manifest = json.loads(unescape(manifest_attr))
    with open(LOG, "a") as fh:
        fh.write(json.dumps(manifest) + "\n")
    seen["name"] = manifest["name"]
    urllib.request.urlopen(f"{url}callback?state={state}&code=c", timeout=10).read()


def connect(url, page):
    state = re.search(r'STATE = "([^"]+)"', page).group(1)
    for slug, pem in WORLD.get("download", {}).items():
        (Path.home() / "Downloads" / f"{slug}.2026-01-02.private-key(1).pem").write_text(pem)
    # Each answer is written before the next request: the run exits once a
    # status that says done has been served.
    for role, pem in WORLD.get("upload", {}).items():
        Path(LOG + ".status").write_bytes(urllib.request.urlopen(urllib.request.Request(
            f"{url}key/{role}?state={state}", data=pem.encode(), method="POST"), timeout=10).read())
    for _ in range(50):
        status = urllib.request.urlopen(f"{url}status", timeout=10).read().decode()
        if json.loads(status)["done"]:
            return
        Path(LOG + ".status").write_text(status)
        time.sleep(0.2)


def fake_open(url):
    def click():
        page = urllib.request.urlopen(url, timeout=10).read().decode()
        manifest = re.search(r'name="manifest" value="([^"]*)"', page)
        if manifest:
            create(url, page, manifest.group(1))
        else:
            connect(url, page)
    Path(LOG + ".opened").touch()
    threading.Thread(target=click, daemon=True).start()
    return True


def fake_convert(code):
    name = seen["name"]
    return {"id": len(name), "pem": f"PEM for {name}", "slug": name, "owner": {"login": "tester"}}


def fake_lookup(slug):
    app = APPS.get(slug)
    if app is None or app.get("hidden"):
        return None
    return {"slug": slug, "app_id": str(app["id"]), "owner": app["owner"],
            "owner_type": bootstrap.owner_type_of({"owner": owner_of(app)})}


def fake_prove(app_id, pem):
    """GitHub finds the App by the JWT's issuer and checks the signature against
    that App's keys, so a key answers only under its own App's ID."""
    slug = WORLD.get("keys", {}).get(pem.strip())
    if slug is None or str(APPS[slug]["id"]) != str(app_id):
        raise bootstrap.KeyRefused("GitHub did not accept that key.")
    app = APPS[slug]
    return {"id": app["id"], "slug": slug, "owner": owner_of(app),
            "permissions": app.get("permissions", ALL_PERMISSIONS),
            "html_url": f"https://github.com/apps/{slug}"}


bootstrap.webbrowser.open = fake_open
bootstrap.convert_manifest = fake_convert
bootstrap.lookup_app = fake_lookup
bootstrap.prove_key = fake_prove
bootstrap.gh_login = lambda: os.environ.get("BOOTSTRAP_LOGIN", "tester")
sys.argv = ["bootstrap.py"] + sys.argv[3:]
sys.exit(bootstrap.main())
