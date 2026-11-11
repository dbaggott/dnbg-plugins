# Setup: agent roles

Part of the `setup` skill. Read this when `roles` is in the check's `open`.
Act on the `check=roles` line's `state`.

## `state=unconfigured`

Each role in `unconfigured=` has no GitHub App and refuses to post as the
user's own account, so nothing it posts can run. For the reviewer that is every
PR review and every spec review: an independent verdict needs an identity that
is not the author's.

Tell the user that, and that creating an App is a click in the browser per role
and an install on the accounts and repos they choose, with the key staying on
this machine. Then load the `reviewer-setup` skill and follow it for the roles
in `unconfigured=`. It creates and installs the Apps; nothing here repeats its
steps.

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
