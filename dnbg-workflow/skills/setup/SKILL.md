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
time: say nothing about a later check until the one before it is done. Each has
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
loaded with, so where it was set during this run, count `owners` as closed.

Then give the whole of it in one summary, so nothing said along the way is
lost among the questions. Use this shape, a line each, leaving out a line that
does not apply:

> **dnbg-workflow setup**
>
> - **Repos:** every repo under `<account>` and `<account>`. *(or: none.)*
> - **Reviewer bot:** set up. *(or: not set up, so no review can run.)*
> - **Other roles:** `<role>` and `<role>` post as your own account. *(the roles
>   in `fallback=`; or: each has its own bot.)*
> - **Restart Claude Code** for the repos to take effect. *(only when `owners`
>   was saved during this run)*
> - **Still open:** `<what is left, in plain words>`. *(or: nothing. Setup is
>   complete.)*
>
> Run `/dnbg-workflow:setup` at any time to pick up what is left or change an
> answer.

**Repos** is the list saved during this run, else `value=` on the `check=owners`
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
heading, and ask about none of them:

- **`retrospectives`**, with its state from the check: on, every agent role
  writes a file on where the process slowed it when its work ends, for
  `process-review` to find the patterns in. Set with
  `/plugin configure dnbg-workflow`.
- **`version_stamp`**, with its state from the check: on, PR descriptions,
  reviews and issue claims carry a hidden comment naming the plugin version.
  Set in the same place.
- **Bots for the roles in `fallback=`** on the `check=roles` line, when it
  names any: `reviewer-setup` creates their Apps.
- **Auto-update**: `/plugin`, then **Marketplaces**, **dnbg**, **Enable
  auto-update**.
- **`summary_dir`**, when `installed=` on the `check=plugins` line names
  `dnbg-agent-summaries`: where summary files are written, set with
  `/plugin configure dnbg-agent-summaries`.
- **`owners` on `dnbg-work-summary`**, when `installed=` names that plugin:
  whose repos a recap searches, set with `/plugin configure dnbg-work-summary`.
  It is a separate setting from this plugin's `owners`.
