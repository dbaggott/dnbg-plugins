# Setup: agent roles

Part of the `setup` skill. Read this when `roles` is in the check's `open`.
Act on the `check=roles` line's `state`.

## `state=unconfigured`

Each role in `unconfigured=` has no GitHub App and refuses to post as the
user's own account, so nothing it posts can run. For the reviewer, say this and
no more:

> Next, the reviewer bot. It reviews your PRs and issues under its own GitHub
> identity, and no review can run without it. It takes two clicks in the
> browser: one to create it, one to install it.

Then load the `reviewer-setup` skill and follow it for the roles in
`unconfigured=`. It creates and installs the Apps; nothing here repeats its
steps. Where it has you name the accounts to install on, they are the ones
`owners` holds: those saved during this run, else `value=` on the `check=owners`
line.

While there, offer the roles in `fallback=` as optional: they work now, posting
as the user's own account, and `reviewer-setup` gives each its own bot identity
in the same run.

## `state=error`

`reason=` is the role resolver's, and every role call fails until it is fixed:

- **`shared-identity`**: two roles are configured with one App. Each needs its
  own; `reviewer-setup` creates one.
- **`bad-config`**: a role's config-directory variable holds a path the
  resolver refuses. Run `"<skill-dir>/../../scripts/as-role.sh" --roles` and
  relay its stderr, which names the role, the variable and the fix.
- **`bad-role-data`** or **`no-answer`**: the plugin's own role data did not
  read, which no setting of the user's causes. Run the same command, relay what
  it prints, and offer to file it upstream per the always-on rule "When shipped
  tooling doesn't fit, tell the user".
