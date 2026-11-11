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

The question is **"Which GitHub accounts do you want to use dnbg-workflow on?
(Repos are chosen later.)"**, with nothing said before it, and where a picker
takes a header, it is "Accounts". How it is
asked depends on how many accounts step 1 found. Without `AskUserQuestion`, ask
it as the typed form whatever the count.

### Up to 8 accounts: checkboxes

One `AskUserQuestion` call, every question `multiSelect: true`, four accounts
to a question. Each option's label is the account's bare name and its
description the empty string, which the picker accepts and shows as the name
alone. There is no None option: ticking nothing is none. A question needs two
options, so move an account over from the page before rather than leave one
alone on the last page, and with a single account in all, add a second option
labelled "None" and described "No accounts." With more than one question, each
ends "(1 of 3)", "(2 of 3)" and so on. The picker's own "Other" takes an
account that is not listed.

The answer is every account ticked on any page; a page that comes back with
no answer had nothing ticked. When the whole call comes back unanswered, which
is how the picker reports both a submit with nothing ticked and a dismissal,
ask in one line, "Nothing was ticked. No accounts, then?", and take a yes as
none.

### More than 8 accounts: ask how to choose

One single-select question, "You belong to `<n>` GitHub accounts. How do you
want to pick the ones dnbg-workflow applies to?":

1. **"Name the ones to include"**: "I'll list them; you type the ones you want."
2. **"Name the ones to leave out"**: "Everything on the list except the ones you
   type."
3. **"Checkboxes"**: "Tick them off, four to a page."
4. **"None"**: "No accounts."

On the first: "Your accounts: `<account>`, `<account>`, … Which ones do you want
to include?" On the second, the same list and "Which ones do you want to leave
out?", then one line saying the list is fixed as of today, so an org they join
later is added by running setup again. On the third, the checkbox form above,
in as many calls as the accounts need at four questions a call.

### The typed form

> Which GitHub accounts do you want to use dnbg-workflow on? (Repos are chosen
> later.) Yours are `<account>`, `<account>`, `<account>`. Name any of them,
> another account, or none.

### Reading the answer

An answer that names repos rather than accounts gets the accounts that own
them, with one line saying the setting covers every repo of an account. Explain
further only if asked: a repo is covered when its `origin` is on github.com
under a listed account, names match whole and ignore case, and in a covered repo
edits to tracked files in the main checkout, and `gh issue create` before
`issue-workflow` is loaded, are blocked.

## 3. Save

Say nothing after a save: the closing summary in `SKILL.md` step 3 names what
was recorded and how to change it.

**An answer of none**, with `owners` empty, saves nothing. An answer of none
that replaces a list is saved as below, with an empty value.

**Any other answer**: the value is the accounts as one comma-separated line.
When `self=` on the `check=plugins` line names an id, save it without asking
again:

```bash
jq -n --arg owners '<value>' '{owners: $owners}' \
  | claude plugin configure <id> --values-stdin
```

At `self=none`, or when that command fails, as it does on a client too old to
have it, the user sets it. Say:

> Set it yourself with `/plugin configure dnbg-workflow`: paste `<value>` into
> **owners**. Tell me when it's done.
