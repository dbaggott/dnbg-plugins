---
name: reviewer-setup
description: One-time setup giving each agent role your own GitHub App, created on your first machine and connected with a key of its own on every other, so the `reviewer` skill (and any other role defined under `roles/`) posts under an independent bot identity rather than your personal account — GitHub access only, no cloud infrastructure, no shared secret. Load when asked to set up the reviewer bot, create your reviewer App or a role's App, connect a machine to a bot that already exists, when the `reviewer` skill or `as-role.sh` reports a role is not set up, or to repair or rotate a role's credentials. Each App's private key stays on this machine.
---

# Role App setup

This is the **one-time** bootstrap for the agent roles' identities. For each
role you choose it creates a per-developer **GitHub App**, so that role posts
under a distinct bot identity (e.g. `agent-reviewer-<you>[bot]`) instead of your
personal account. For the reviewer, that separate identity is what makes the
agent an *independent* reviewer and what lets it post a binding `--approve` /
`--request-changes` verdict on any PR — including one you authored, which
GitHub forbids when you review as yourself.

A role's App is created once. Every other machine connects to it with a private
key of its own, and never creates another.

A role is a directory under the plugin's `roles/`, holding the permissions its
App is created with; `ls "<skill-dir>/../../roles"` lists them. A role with no
App behaves as its `permissions.json` says: the reviewer refuses to run at all,
and a role whose `fallback` is `operator` acts as your own account, which a
session-start notice names.

Everything runs on **GitHub access only**. Each App's private key is generated
during creation, saved on this machine (mode 600), and never leaves it;
`scripts/as-role.sh` signs a short-lived token from it each time the role acts.
No cloud service, no shared secret store.

GitHub Apps are a GitHub construct with no GitLab or Bitbucket equivalent, so
this setup is **GitHub-only** with nothing to degrade to. It is also **not
scoped to any repository** — it creates one App on your machine and installs it
on the accounts you name. Never gate it on the working directory: running it
from a checkout of some other forge's repo, or from no repo at all, is normal
and must work.

## Before you start

- Run from a machine where `gh` is authenticated (`gh auth status`), plus
  `python3`, `openssl`, `jq`, and `curl` available (the setup and review
  helpers need them).
- A role whose credentials already exist (default
  `~/.config/dnbg/<role>/config.json`) is set up; the bootstrap skips it unless
  you name it. Naming it in `--roles` is refused: `--adopt <role>=<slug>`
  connects this machine to the same App again, replacing its key here, and a
  new App for the role, after deleting the old one or beside it, takes
  `--name`; only do that deliberately.

## Ownership model

A GitHub App's owner determines where it can be installed, and a **private** App
can only be installed on the account that owns it. To review **both** an org's
repos and your **personal** repos with one bot, it has to be installable on two
different accounts — which forces a **public, user-owned** App. That's the
default, for every role:

- **User-owned, public** (default) — created under your account; public so it can
  be installed on an org *and* on your personal account. Covers org repos +
  your personal repos. `as-role.sh` resolves the right installation per repo.
- **Org-owned, private** (`--owner-type org --org <login>`) — belongs to the org,
  installs on org repos **only** (no personal repos). Use this only if you want a
  centrally-managed, non-public bot and don't need personal-repo review.

"Public" only means the App is listed and others *could* install it on their own
account; it has no webhook and no server — just an identity whose key you hold —
so someone installing it elsewhere grants access to *you*, not the reverse. Worth
a nod before creating, not a real exposure.

## Run the bootstrap

`bootstrap.py` is in this skill's directory (the **Base directory** shown when
this skill loads). It connects the roles whose App exists and creates the rest.

### Find the bots that already exist

Unless the skill that sent you here says which roles to connect, ask the
bootstrap, exactly as written, single quotes included, adding `--roles` when
the operator named some. A `user_config` placeholder still standing in it is an
option nobody has set, which the script reads as unset:

```bash
python3 "<skill-dir>/bootstrap.py" --detect --owners='${user_config.owners}'
```

It prints a JSON entry per role and changes nothing. `"state": "yours"` is a
bot the operator already has, with its `slug`: connect it. `"state": "free"` is
a role to create. It cannot see every App, so `free` is not proof the operator
has none.

### Confirm

Confirm with the operator which roles to set up before running it, unless the
skill that sent you here already has their go-ahead. Describe a role's App in
one line, as a GitHub App under their account that gives the role's activity
its own identity, separate from theirs, and for a role that is `yours`, as
their `<slug>`, which already exists and gets a key for this machine. When you
ask with a picker, label the go-ahead option "Create (Recommended)" and nothing
more, or "Connect (Recommended)" when every role asked about is `yours`. End
the question "Already have a bot under another name? Say so." The Apps are
publicly listed ("Ownership model" above); say so when asked.

An operator with a bot under another name gives, per role, its slug or the URL
of its settings page, whose last part is the slug. Connect it as one detected
`yours`. When the run answers that the App cannot be looked up, ask for the
**App ID** shown on that settings page and pass `--adopt <role>=<slug>:<App ID>`.

### Run it

One run, with `--adopt <role>=<slug>` for each role to connect and `--roles`
naming the roles to create:

```bash
# connect one role and create two:
python3 "<skill-dir>/bootstrap.py" --adopt reviewer=<slug> --roles author,orchestrator

# connect only:
python3 "<skill-dir>/bootstrap.py" --adopt reviewer=<slug> --adopt author=<slug>

# create only: a chosen subset, or with no --roles every role not yet set up:
python3 "<skill-dir>/bootstrap.py" --roles reviewer

# create org-only, private (no personal repos):
python3 "<skill-dir>/bootstrap.py" --roles reviewer --owner-type org --org <org-login>
```

A create for a role whose bot it finds is refused, naming the `--adopt` to pass
instead.

**Connecting** comes first, on one browser page with a row per role. GitHub has
no API that generates an App's private key, so the operator opens each App's
settings from its row, finds its credentials there and generates a new
**private key**, which is not a client secret. The page picks
the downloaded key up from `~/Downloads`, checks with GitHub that it is that
App's key, saves it, and removes the download. Each row also takes the file
through a file picker, for a download saved elsewhere or a browser on another
machine. A key downloaded before the page opened is not picked up: an operator
who already has the key file skips the page for that role with
`--key <role>=<path>`. Nothing is installed: the App's installations are
already in place.

**Creating** follows, a role at a time: the browser opens a local page that
immediately forwards to GitHub, where the **one step it can't automate** is the
click GitHub requires to create any App: press **"Create GitHub App"**. GitHub
redirects back to the local server, which saves the new App's key and moves to
the next role.

At the end it prints a JSON list with each role's `action` (`connected` or
`created`), App slug, config dir, and **install URL**. A failure stops the run
and names the roles it did not reach; the roles before it stay set up.

The run waits on the browser, so say this in the same message as the call that
starts it, with the port you passed, 8765 by default:

> Opening your browser. If nothing opens, go to `http://localhost:<port>/`.

On a machine with no browser of its own (headless, SSH), pass `--no-browser`
and have the operator forward the port and open that URL.

## Install the App

Creation does not install an App — an App with no installation can't mint a
token. A connected App is installed already, so this section is for the Apps
the run created. The run's last browser page carries an install button for each App it
created (`https://github.com/apps/<slug>/installations/new`) and says how to
choose the repos: all of an account's, which it recommends for the least
upkeep, or a selected list. Each App is installed on **each account whose repos
that role will work on**.

When the operator asks which to choose, give them the trade: the reviewer App
needs `contents: write` to review at all — GitHub gates resolving a thread and
having a verdict counted on it, with no narrower grant — so a leaked key can
write source on every repo the App is installed on, and the repo list is the
one lever that narrows it. `SECURITY.md` states each role's blast radius.

- **Your personal account** — for your personal repos. You install it directly.
- **Each org** — for that org's repos. An org owner approves the install (you can
  self-approve if you're an owner).

Each account is a separate installation; `as-role.sh` resolves the right one per
repo each time the role acts, so install on every account you intend the role to
work on. (An **org-owned** App, if you chose `--owner-type org`, installs on the
org only.)

When the run ends, tell the operator in this shape and no longer. The last
browser tab already shows an install button for each bot the run created, so
repeat neither the URLs nor why an App needs installing:

> The `<role>` bot is created: `<slug>`. *(or: The `<role>`, `<role>` and
> `<role>` bots are created.)*
>
> One step left: click **Install** for each in the browser tab. The page says
> how to choose the repos.
>
> Tell me when it's done.

For the roles the run connected, say "connected" in place of "created" and ask
for no install: "The `<role>` bot is connected: `<slug>`." A run that only
connected ends there, and you go straight to **Verify**.

A run that stopped early showed no install buttons: give the install URL of
each bot it did create, from the JSON it printed.

Name the accounts to install it on when you know them.

Keep the key's mechanics out of what you tell the operator: where the
credentials were saved, which config directory or variable is in force, and
what you will or will not do with the key. Raise them only when asked, or when
a step fails and the fix is there.

## Verify

Confirm each role can act on each account you installed it on, through the same
resolver every caller uses. The token is minted for the account, so the repo
name is not looked up and you need not ask for one:

```bash
"<skill-dir>/../../scripts/as-role.sh" <role> <your-login>/_ -- true && echo "ready: personal"
"<skill-dir>/../../scripts/as-role.sh" <role> <org-login>/_ -- true && echo "ready: org"
```

A quiet run, apart from the resolver's `as=` line, means setup is complete for
that account. If it reports "not installed on" the account, the install step
didn't land, or a connected App was never installed there: complete it at
`https://github.com/apps/<slug>/installations/new` and retry.

## What got stored

In each role's config dir: `$XDG_CONFIG_HOME/dnbg/<role>/` when
`XDG_CONFIG_HOME` is set, else `~/.config/dnbg/<role>/`. Override it with
`DNBG_<ROLE>_CONFIG_DIR` (the role name upper-cased), an absolute path or one
starting with `~/`, exported before the bootstrap and every later role call:

- `private-key.pem` — the App private key (mode 600). **Never commit or share
  it**; it's the bot's full credential. Each machine has its own, up to the 25
  keys GitHub allows an App, so losing the laptop means deleting that one key
  in the App's settings.
- `config.json` — `app_id`, `slug`, `bot_login`, owner. `installation_id` stays
  blank by design: the App can have several installations (org + personal), so
  `as-role.sh` resolves the right one per repo each time.

The directory itself is created `0700`, and the mint refuses to use it if
it is group- or world-writable. That is not belt-and-braces on the `0600` file
mode: a key that cannot be *read* by others can still be *replaced* by anyone who
can write the directory, and the next mint would sign with theirs.

## Keeping the key somewhere other than a file

The plaintext PEM is the default, not the only option — see `docs/configuration.md`'s
"Role Apps' private keys". Two alternatives, both resolved
ahead of the file (shown for the reviewer; every role has its own
`DNBG_<ROLE>_*` set):

- `DNBG_REVIEWER_PRIVATE_KEY` — the PEM itself. With `DNBG_REVIEWER_APP_ID` it
  needs no config dir at all, which is what makes CI and headless runs possible.
  `DNBG_REVIEWER_INSTALLATION_ID` is optional there and saves the
  `/app/installations` round trip, and `DNBG_REVIEWER_SLUG` gives the login the
  watches filter on.
- `DNBG_REVIEWER_PRIVATE_KEY_COMMAND`, or `private_key_command` in `config.json`
  — a command whose stdout is the PEM. This is the hook for any secret manager:

  ```
  op read "op://Private/reviewer/private key"
  pass show reviewer/private-key
  security find-generic-password -s dnbg-reviewer -w
  ```

`bootstrap.py` deliberately does not write to a manager. It writes the file; move
it wherever you want and set the command.

## Repair / rotate

- **Lost or leaked key**: delete that key in the App's GitHub settings, which
  is also how one machine is revoked. GitHub keeps an App's last key until
  another exists, so where it is the only one, connect first. To give this
  machine a new key, connect again with `--adopt <role>=<slug>`. Where you
  deleted the App instead, `--roles <role> --name <name>` creates a new one:
  the role is still set up on this machine, so the create needs the name. `SECURITY.md`
  has the order.
- **Re-install on more repos**: just adjust the installation's repo access in
  GitHub; no re-bootstrap needed.
- **A permission is missing** (the mint said so, or a call is failing with
  `Resource not accessible by integration`): re-running the bootstrap does
  **not** fix an App that already exists — the manifest is only read at
  creation. Edit the permissions on the App itself, under *Permissions &
  events* at `https://github.com/settings/apps/<slug>`.

  **Then accept the change on every installation, separately.** A permission
  added to an App stays *pending* until each account it is installed on accepts
  it; until then the granted set is the old one and the failure is unchanged, so
  the edit looks like it did nothing. Personal installs you accept yourself; an
  org install needs an org owner.

  Then run **Verify** again. The mint reads what was actually granted, so a quiet run is
  the confirmation — and the App's own settings page is not, since it shows what
  the App *asks* for, which flips the moment you save.
