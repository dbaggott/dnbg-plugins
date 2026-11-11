# Setup: `owners`

Part of the `setup` skill. Read this when `owners` is in the check's `open`.

Read the user's accounts:

```bash
gh api user --jq .login; gh api user/orgs --jq '.[].login'
```

Then ask, in this shape and no longer:

> Which repos do you want to use dnbg-workflow on? It is set per GitHub
> account: `<login>`, `<org>`, `<org>`. Name any of them, another account, or
> none.
>
> In those repos every change goes through a worktree and a draft PR. Everywhere
> else the workflow is only advice.

List the accounts on one line, as names alone: no note on what each is, and no
spelled-out combinations. Past ten, list the login and say how many orgs there
are instead of naming them.

An answer that names repos rather than accounts gets the accounts that own
them, with one line saying the setting covers every repo of an account. Explain
further only if asked: a repo is covered when its `origin` is on github.com
under a listed account, names match whole and ignore case, and in a covered repo
edits to tracked files in the main checkout and `gh issue create` before
`issue-workflow` is loaded are blocked.

**None is a valid answer**, and the right one for a project-scope install
shared with a team. Step 3 of `SKILL.md` covers the session-start message for a
user who answers none.

For any other answer, the value is the accounts as one comma-separated line.
When `self=` on the `check=plugins` line names an id, show the user the value,
and on their go-ahead save it:

```bash
jq -n --arg owners '<value>' '{owners: $owners}' \
  | claude plugin configure <id> --values-stdin
```

Tell them it applies to every repo on the machine once Claude Code restarts.

At `self=none`, or when that command fails, as it does on a client too old to
have it, the user sets it: give them the value and
`/plugin configure dnbg-workflow`, or `/plugin`, then **Installed**,
`dnbg-workflow`, **Configure options**, and ask them to say when it is set.

Either way, a new session's `/dnbg-workflow:setup` confirms it.
