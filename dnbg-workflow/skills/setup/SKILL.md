---
name: setup
description: Check what a dnbg-workflow install still needs and walk the user through only that — which repos the workflow applies to, the reviewer bot, a missing tool or `gh` login — then name the optional extras. Load when asked to set up dnbg or the dnbg plugins, check the dnbg setup, say what is left to set up, finish setup or finish configuration, or change which repos dnbg-workflow applies to. Run it again at any time; it re-reads the state and keeps no progress of its own. Skip for creating or repairing a role's GitHub App when that is all that was asked, which is `reviewer-setup`.
---

# Setup

`<skill-dir>` is the **Base directory** announced when this skill loads.

## 1. Read the state

Run this exactly as written, single quotes included. A `user_config`
placeholder still standing in it is an option nobody has set, which the script
reads as unset:

```bash
"<skill-dir>/../../scripts/setup-check.sh" --owners='${user_config.owners}' \
  --retrospectives='${user_config.retrospectives}' --version-stamp='${user_config.version_stamp}'
```

It prints one `check=<name> state=<state> …` line per check, then
`result=OK setup=<complete|incomplete> open=<check,…|none>`. On
`result=ERROR reason=bad-args` the command was altered: run it again as written.

## 2. Walk what is open

Asked to change which repos the workflow applies to, or invoked with `owners`,
read `references/owners.md` and walk it whether or not `owners` is open, then go
to step 3.

Otherwise, at `setup=complete`, ask nothing and go to step 3.

Otherwise take the checks `open` names, in the order it lists them, one at a
time. Go from one check's question straight to the next: no message in between
confirming what was just done or introducing what comes next, since step 3's
summary carries all of it. Each has
one reference. Read a reference only when its check is in `open`:

| In `open` | Read |
| --- | --- |
| `tools`, `gh-auth` or `claude-code` | `references/environment.md` |
| `owners` | `references/owners.md` |
| `roles` | `references/roles.md` |

The user may stop at any check. Go to step 3 with whatever is left.

## 3. Close

If you walked any check, run step 1's command again and read `open` from the
new result, with one correction: the command carries the `owners` this skill
loaded with, so where it was set during this run, count `owners` as closed,
without telling the user about the correction.

Then give the whole of it in one summary, so nothing said along the way is
lost among the questions. Use this shape, a line each, leaving out a line that
does not apply:

> **dnbg-workflow setup**
>
> - **Accounts:** `<account>` and `<account>`. *(or: none.)*
> - **Reviewer bot:** set up. *(or: not set up, so no review can run.)*
> - **Other roles:** `<role>` and `<role>` post as your own account. *(the roles
>   in `fallback=`; or: each has its own bot.)*
> - **Restart Claude Code** for the accounts to take effect. *(only when `owners`
>   was saved during this run and something is still open; otherwise the
>   welcome says it)*
> - **Still open:** `<what is left, in plain words>`. *(or: nothing. Setup is
>   complete.)*
>
> Run `/dnbg-workflow:setup` at any time to pick up what is left or change an
> answer.

**Accounts** is the list saved during this run, else `value=` on the `check=owners`
line. **Still open** names each check left in `open`, with a missing tool by
name.

A session-start message repeats while `owners` or `roles` is open, until the
marker file on the `check=marker` line exists. When the user has said they are
leaving one of those two as it is, write the marker, and tell them that the
message is now off and that deleting that file brings it back:

```bash
mkdir -p "$(dirname "<path>")" && touch "<path>"
```

After the summary, name the optional extras, once, a line each, under their own
heading, and ask about none of them. When nothing is open, end on the welcome
below the list:

- **Auto-update (recommended)**: "gets you bug fixes and enhancements as they
  ship. Turn it on with `/plugin`, then **Marketplaces**, **dnbg**, **Enable
  auto-update**."
- **Bots for the roles in `fallback=`** on the `check=roles` line, when it
  names any, recommended: "`<role>` and `<role>` post as you. Say *create the
  `<role>` and `<role>` bots* to give them their own identities." Asked for
  them, read `references/roles.md` and ask its questions for those roles.
- **Retrospectives**, with its state from the check: on, every agent role
  writes a file on where the process slowed it when its work ends, for
  `process-review` to find the patterns in. Set with
  `/plugin configure dnbg-workflow`.
- **Version stamp**, with its state from the check: on, PR descriptions,
  reviews and issue claims carry a hidden comment naming the plugin version.
  Set in the same place.
- **Where summary files are written**, when `installed=` on the `check=plugins`
  line names `dnbg-agent-summaries`: "`~/.claude/dnbg-agent-summaries` unless
  you change it, with `/plugin configure dnbg-agent-summaries`."

Name each by the words above, never by its option's key.

**The welcome** is the last thing said when nothing is open, in this shape. Its
first line is "Restart Claude Code, then try it:" when `owners` was saved during
this run:

> **Welcome to dnbg-workflow.** You're ready to go.
>
> Try it: open a session in one of your repos and ask for a change. You'll get
> a worktree, a draft PR and an offer to send it to review.
>
> For something bigger: *I want to plan out `<the work>`. File an issue for it.*
