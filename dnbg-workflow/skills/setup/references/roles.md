# Setup: agent roles

Part of the `setup` skill. Read this when `roles` is in the check's `open`, and
act on the `check=roles` line's `state`. Read it too when the user asks for a
role's bot: then ask "The questions" below for the roles they named.

## `state=unconfigured`

Each role in `unconfigured=` has no GitHub App and refuses to post as the
user's own account, so nothing it posts can run. Each role in `fallback=` has
none either and posts as the user until it does.

### The questions

Say nothing before the question. Ask about every role in `unconfigured=` and
then every role in `fallback=`, with `AskUserQuestion`, or in one line without
it.

First find which of those roles already have a bot, created from another
machine. `<owners>` is the accounts `owners` holds, those saved during this
run, else `value=` on the `check=owners` line; with none, leave the flag out:

```bash
python3 "<skill-dir>/../reviewer-setup/bootstrap.py" --detect \
  --roles <role,…> --owners=<owners>
```

It prints a JSON entry per role and changes nothing. A role whose `state` is
`yours` has a bot, named by its `slug`, to connect this machine to; any other
is created. When the command fails, relay what it printed in place of the
question.

Each role's words:

| Role | What its bot gives | Without it |
| --- | --- | --- |
| `reviewer` | "reviews their own identity" | "No review can run without it." |
| `author` | "your PRs and issues their own identity" | "Without it they post as you." |
| `orchestrator` | "an orchestrator's issue comments their own identity" | "Without it they post as you." |

**Two or more roles: one question with a checkbox each**, `multiSelect: true`:

- Question: "Create the bots? Each is a GitHub App under your account,
  separate from yours. A few quick clicks in the browser: create and install
  each. Already have a bot under another name? Say so." With any role `yours`,
  it opens "Set up the bots?" in place of "Create the bots?".
- An option per role, labelled "`<Role>` bot (Recommended)" and described
  "Gives `<what its bot gives>`. `<Without it>`", as in "Reviewer bot
  (Recommended)", "Gives reviews their own identity. No review can run without
  it."
- For a role that is `yours`, the option is labelled "`<Role>` bot: connect
  (Recommended)" and described "Your `<slug>` already exists. A few clicks in the
  browser add a key for this machine."

The roles ticked are the ones to set up. When the call comes back unanswered,
which is how the picker reports both a submit with nothing ticked and a
dismissal, ask in one line, "Nothing was ticked. No bots, then?"

**One role: a single-select question**:

- Question: "Create the `<role>` bot? It's a GitHub App under your account
  that gives `<what its bot gives>`, separate from yours. `<Without it>`
  Already have one under another name? Say so." For a role that is `yours`, it
  opens "Connect the `<role>` bot?" and has no last sentence.
- **"Create (Recommended)"**, first: "A few quick clicks in the browser: create
  and install it." For a role that is `yours`, **"Connect (Recommended)"**:
  "Your `<slug>` already exists. A few clicks in the browser add a key for this
  machine."
- **"Not now"**: "Reviews stay off until it exists." for the reviewer, and for
  another role "Its work keeps posting as you."

Load the `reviewer-setup` skill and follow it for the roles chosen, all in one
run, from its "Run it" on: the question was its confirmation, and the roles
that are `yours`, with their slugs, are the ones it connects. A user who says
they have a bot under another name is its "Confirm" section's case. It connects,
creates and installs the Apps; nothing here repeats its steps. Where it has you
name the accounts to install on, they are the ones `owners` holds: those saved
during this run, else `value=` on the `check=owners` line.

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
