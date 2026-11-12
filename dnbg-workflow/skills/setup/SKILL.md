---
name: setup
description: Show how a dnbg-workflow install is set up, after walking the user through only what it still needs — which repos the workflow applies to, the reviewer bot, a missing tool or `gh` login. Load when asked to set up dnbg or the dnbg plugins, check or show the dnbg setup, say what is left to set up, finish setup or finish configuration, or change which repos dnbg-workflow applies to. Run it again at any time; it re-reads the state and keeps no progress of its own. Skip for creating or repairing a role's GitHub App when that is all that was asked, which is `reviewer-setup`.
---

# Setup

`<skill-dir>` is the **Base directory** announced when this skill loads.

## 1. Read the state

Run this exactly as written, single quotes included. A `user_config`
placeholder still standing in it is an option nobody has set, which the script
reads as unset:

```bash
"<skill-dir>/../../scripts/setup-check.sh" --owners='${user_config.owners}' \
  --retrospectives='${user_config.retrospectives}' --version-stamp='${user_config.version_stamp}' \
  --setup-notice='${user_config.setup_notice}'
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
list carries all of it. Each has one reference. Read a reference only when
its check is in `open`:

| In `open` | Read |
| --- | --- |
| `tools`, `gh-auth` or `claude-code` | `references/environment.md` |
| `owners` | `references/owners.md` |
| `roles` | `references/roles.md` |

The user may stop at any check. Go to step 3 with whatever is left.

## 3. Show the setup

If you walked any check, run step 1's command again and read `open` from the
new result, with one correction: the command carries the `owners` this skill
loaded with, so where the accounts were saved during this run, count `owners`
as closed for a list and open for none, without telling the user about the
correction.

Then show the whole setup in this shape, a line each, with nothing said about
it before or between:

> **Your dnbg-workflow setup**
>
> - ❌ **Tools:** `<tool>` and `<tool>` are missing. Install them, then run
>   `/dnbg-workflow:setup` again.
> - ❌ **gh login:** not logged in. Type `! gh auth login`, then run
>   `/dnbg-workflow:setup` again.
> - ❌ **Claude Code:** `<version>`, older than `<floor>`. Update it, then run
>   `/dnbg-workflow:setup` again.
> - ✅ **Accounts:** `<account>` and `<account>`. Change with
>   `/dnbg-workflow:setup owners`. *(or: ❌ none, so the workflow applies to no
>   repo. Set them with `/dnbg-workflow:setup owners`.)*
> - ✅ **Reviewer bot:** set up. *(or: ❌ not set up, so no review can run. Say
>   "create the reviewer bot".)*
> - ✅ **Author bot:** set up. *(or: ➖ posts as you. Say "create the author
>   bot" to give it its own identity.)*
> - ✅ **Retrospectives:** on. Change with `/plugin configure dnbg-workflow`.
>   *(or: ➖ off. On, every agent role writes a file on where the process slowed
>   it down. Change with `/plugin configure dnbg-workflow`.)*
> - ✅ **Version stamp:** on. Change with `/plugin configure dnbg-workflow`.
>   *(or: ➖ off. On, PRs, reviews and issue claims carry a hidden comment
>   naming the plugin version. Change with `/plugin configure dnbg-workflow`.)*
> - ✅ **Summary files:** `<path>`. Change with
>   `/plugin configure dnbg-agent-summaries`.
> - ➖ **Auto-update:** recommended. Turn it on with `/plugin`, then
>   **Marketplaces**, **dnbg**, **Enable auto-update**.
> - ✅ **Incomplete setup notice:** on. Turn it off with
>   `/plugin configure dnbg-workflow`. *(or: ➖ off. Turn it on with
>   `/plugin configure dnbg-workflow`.)*
>
> More settings and details:
> https://github.com/dbaggott/dnbg-plugins/blob/main/docs/configuration.md

Every ❌ line comes first, then the rest, each group in the order above. Which
lines there are, and what each says:

- **Tools**, **gh login** and **Claude Code** each appear only while its check
  is in `open`.
- **Accounts** is the list saved during this run, else `value=` on the
  `check=owners` line. Where `references/owners.md` left a value unsaved, the
  line is the ❌ it gives.
- **A bot line for every role** on the `check=roles` line: ✅ in `configured=`,
  ❌ in `unconfigured=`, ➖ in `fallback=`, each worded as the reviewer's or the
  author's line above. At `state=unknown` there is one line in their place,
  "❌ **Bots:** can't be checked until `jq` is installed.", and at
  `state=error` one "❌ **Bots:**" line saying what `references/roles.md` says
  of its `reason=`.
- **Retrospectives** and **Version stamp** take their state from their checks.
- **Summary files** appears when the `check=summary-dir` line has a `value=`,
  which is the path.
- **Incomplete setup notice** appears only while `open` names a check, with its
  state from the `check=setup-notice` line.

Name each by the words above, never by its option's key. Asked for a bot, read
`references/roles.md` and ask its questions for the roles named.

Two things can follow the list:

- **The welcome**, when step 1's first result read `setup=incomplete` and
  nothing is open now:

  > **Welcome to dnbg-workflow.** You're ready to go!
  >
  > Try it: open a session in one of your repos and ask for a change. You'll
  > get a worktree, a draft PR and an offer to send it to review.
  >
  > For something bigger: *I want to plan out `<the work>`. File an issue for
  > it.*

- **The reload line**, when `owners` was saved during this run, as the last
  thing said: "Run `/reload-plugins` for the new accounts to take effect."
  After the welcome it reads "Run `/reload-plugins` first, for your accounts to
  take effect."
