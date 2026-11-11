# Setup: `owners`

Part of the `setup` skill. Read this when `owners` is in the check's `open`, or
when the user asked to change which repos the workflow applies to.

`owners` is the GitHub accounts, orgs and personal logins, whose repos the
workflow applies to. The wording below is the wording to use: keep to it, and
add no note on what each account is and no spelled-out combinations.

## 1. Read the accounts

```bash
gh api user --jq .login; gh api user/orgs --jq '.[].login'
```

When the `check=owners` line reads `state=set`, open with the list as it
stands, from its `value=`: "dnbg-workflow currently applies to: `<account>`,
`<account>`." The answer below replaces that list.

## 2. Ask

The question is **"Which repos do you want to use dnbg-workflow on?"** How it is
asked depends on how many accounts step 1 found. Without `AskUserQuestion`, ask
it as the typed form whatever the count.

**The None option**, wherever it appears, is labelled "None" and described "No
repos. I only want the skills when I ask for them."

### Up to 8 accounts: checkboxes

One `AskUserQuestion` call, every question `multiSelect: true`, four options to
a question, with "None" as the last option of the last question. Each account's
label is its bare name and its description "Every repo under `<name>`". With
more than one question, each ends "(1 of 3)", "(2 of 3)" and so on. The picker's
own "Other" takes an account that is not listed.

The answer is every account ticked on any page. None ticked, or nothing ticked
anywhere, is none. If the call fails or comes back without an answer for a
page, ask again in the typed form.

### More than 8 accounts: ask how to choose

One single-select question, "You belong to `<n>` GitHub accounts. How do you
want to pick the ones dnbg-workflow applies to?":

1. **"Name the ones to include"**: "I'll list them; you type the ones you want."
2. **"Name the ones to leave out"**: "Everything on the list except the ones you
   type."
3. **"Checkboxes"**: "Tick them off, four to a page."
4. **"None"**, described as above.

On the first: "Your accounts: `<account>`, `<account>`, … Which ones do you want
to include?" On the second, the same list and "Which ones do you want to leave
out?", then one line saying the list is fixed as of today, so an org they join
later is added by running setup again. On the third, the checkbox form above,
in as many calls as the accounts need at four questions a call.

### The typed form

> Which repos do you want to use dnbg-workflow on? It is set per GitHub
> account: `<account>`, `<account>`, `<account>`. Name any of them, another
> account, or none.

### Reading the answer

An answer that names repos rather than accounts gets the accounts that own
them, with one line saying the setting covers every repo of an account. Explain
further only if asked: a repo is covered when its `origin` is on github.com
under a listed account, names match whole and ignore case, and in a covered repo
edits to tracked files in the main checkout, and `gh issue create` before
`issue-workflow` is loaded, are blocked.

## 3. Save

**An answer of none**, with `owners` empty: save nothing, and say:

> Nothing saved. dnbg-workflow won't apply to any repo automatically; the skills
> still work when you ask for them.
>
> To pick repos later, run `/dnbg-workflow:setup owners`.

Step 3 of `SKILL.md` then covers the session-start message. An answer of none
that replaces a list is saved as below, with an empty value.

**Any other answer**: the value is the accounts as one comma-separated line.
Ask "I'll set dnbg-workflow to apply to: `<account>`, `<account>`. Save it?"
When `self=` on the `check=plugins` line names an id, save it on their
go-ahead:

```bash
jq -n --arg owners '<value>' '{owners: $owners}' \
  | claude plugin configure <id> --values-stdin
```

Then say:

> Saved. dnbg-workflow applies to every repo under `<account>` and `<account>`,
> starting the next time you start Claude Code.
>
> To add or remove an account later, run `/dnbg-workflow:setup owners`, or edit
> the list yourself with `/plugin configure dnbg-workflow`.

At `self=none`, or when that command fails, as it does on a client too old to
have it, the user sets it. Say:

> Set it yourself with `/plugin configure dnbg-workflow`: paste `<value>` into
> **owners**. Tell me when it's done.
>
> To add or remove an account later, change that same field.
