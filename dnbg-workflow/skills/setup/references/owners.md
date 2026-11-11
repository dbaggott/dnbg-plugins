# Setup: `owners`

Part of the `setup` skill. Read this when `owners` is in the check's `open`.

`owners` is the list of GitHub orgs and personal logins whose repos the
workflow enforces on. Tell the user what setting it changes:

- A repo is **covered** when its `origin` is on github.com under one of the
  listed accounts. Names match whole and ignore case, so `acme` does not cover
  `acme-corp`.
- In a covered repo, editing a tracked file in the main checkout is blocked, so
  every change goes through a worktree and a draft PR, and `gh issue create` is
  blocked until the `issue-workflow` skill is loaded.
- Everywhere else, and everywhere while the list is empty, nothing is blocked
  and the workflow is advice.

Ask which accounts to enforce on. Offer the candidates:

```bash
gh api user --jq .login; gh api user/orgs --jq '.[].login'
```

**None is a valid answer.** It is the right one for a project-scope install
shared with a team, where the skills and rules load for everyone and how each
person drives their own editor stays their choice. Step 3 of `SKILL.md` covers
the session-start message for a user who answers none.

For any other answer, the value is the accounts as one comma-separated line.
When `self=` on the `check=plugins` line names an id, show the user the value,
and on their go-ahead save it:

```bash
jq -n --arg owners '<value>' '{owners: $owners}' \
  | claude plugin configure <id> --values-stdin
```

It changes that one option, in their user settings, for every repo on the
machine, and takes effect when Claude Code restarts: tell them so.

At `self=none`, or when that command fails, as it does on a client too old to
have it, the user sets it: give them the value and
`/plugin configure dnbg-workflow`, or `/plugin`, then **Installed**,
`dnbg-workflow`, **Configure options**, and ask them to say when it is set.

Either way, a new session's `/dnbg-workflow:setup` confirms it.
