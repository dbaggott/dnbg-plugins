# Issue workflow: filing an issue

Part of the `issue-workflow` skill. Read this when the body is written per
`references/creating.md` and labeled per `references/labeling.md`; `SKILL.md`
carries the host check and "Writing as the author".

## File it

File it as the author (`SKILL.md`, "Writing as the author"), with the body
drafted in your draft directory
(`<skill-dir>/../git-workflow/references/draft-files.md`), and `<skill-dir>`
this skill's Base directory:

```bash
"<skill-dir>/../../scripts/as-role.sh" author <owner>/<repo> -- \
  gh issue create --repo <owner>/<repo> --title "<title>" --body-file <file> \
  --label <label> [--label <label>…]
```

An update to an existing issue is the body edit in "Writing as the author".

When a new or updated body came from a summary file and `dnbg-agent-summaries`
is installed, load its `summary-review` skill and set that summary's status as
its `references/summary.md` says for a summary an issue was filed from, in the
same turn.

## Offer the spec review

Once an issue filed on its own is created, read whether a reviewer is set up,
per `references/spec-review-rounds.md`, "Is a reviewer set up?". On
`result=OK`, ask with `AskUserQuestion`: "Spec-review <URL> now?", `<URL>` being
the issue's.

1. **"Spec-review it now (Recommended)"**: "A reviewer subagent reviews the
   issue from GitHub, and this session answers its rounds as the author."
2. **"Not now"**: "Nothing more happens here. Paste `review <URL> as a spec`
   into a new session when you want the review."

On "Spec-review it now", go straight to `references/spec-review-rounds.md`,
"Spawn the reviewer", without its "Who runs the spec review?" picker, and answer
each round per its "Answering". On "Not now", end with the prompt
`review <URL> as a spec` and nothing else.

The offer is not made for a child filed under `references/decomposing.md`,
whose set goes to review at its step 6; for a tracking issue, which "Is this one
issue or a project?" in `references/creating.md` already hands over; for an
issue filed by `findings-review`, `process-review` or `orchestrate`'s close-out,
which offer the batch form below instead; or for a gap reported upstream, below.

Without `AskUserQuestion`, take "Not now": end with the prompt and say in the
report that the review was not run. This is the default, not a question to post
per `references/delegated.md`.

### With no reviewer set up

On `result=ERROR reason=not-configured`, ask in place of the offer: "No reviewer
bot is set up, so <URL> cannot be spec-reviewed yet. Set it up now?"

1. **"Set up the reviewer bot"**: "Create the reviewer's GitHub App with
   `reviewer-setup`, then decide on the spec review."
2. **"Not now"**: "Nothing more happens here. Once `reviewer-setup` has run,
   paste `review <URL> as a spec` into a new session when you want the review."

On "Set up the reviewer bot", load `reviewer-setup`, then run the read again:
on `result=OK`, make the offer above, and on anything else take "Not now". On
"Not now", end with the prompt `review <URL> as a spec` and one sentence saying
it needs `reviewer-setup` first. Without `AskUserQuestion`, take "Not now" and
say in the report that no reviewer is set up.

On any other `result=ERROR`, make no offer: go on as "Not now" does, with its
`reason=` and the line printed under it in place of the sentence about
`reviewer-setup`.

### Offer the spec review for a batch

A flow that files issues in one pass, one or more, asks once for all it decided
to offer, in place of the question above. The prompt is
`Review <URL>, <URL> as a set.`, one per repo the issues were filed in, naming
that repo's issues. After the same read, ask "Spec-review these issues now?"
with the same two options, the "Not now" description naming these prompts in
place of `review <URL> as a spec`. "With no reviewer set up" applies to a batch
with the same substitution, its "Not now" giving the prompts in the flow's
report and going on with the flow.

On "Spec-review it now", go straight to `references/spec-review-rounds.md`,
"Spawn the reviewer", without its "Who runs the spec review?" picker, and
dispatch once per prompt, with that prompt in place of its
`Review <URL> as a spec.`; answer each round per its "Answering". On "Not now",
give the prompts to paste in the flow's report and go on with the flow.

Without `AskUserQuestion`, take "Not now" and say in the report that the review
was not run, as for a single issue.

## Reporting a gap upstream

An issue filed against someone else's project — reporting that tooling you
installed doesn't fit your case — is governed by the always-on rule "When
shipped tooling doesn't fit, tell the user", not by the operator's own
conventions. Two constraints that don't apply to an issue in your own repo:
it is published under the user's identity to a project they don't control, so
it is filed with their own `gh issue create`, not as the author role, and only if they ask for it and only after they have approved the exact
text; and the body is written from the **generic** case, so the session that
exposed the gap contributes the shape of the problem and none of its content.
Everything `references/creating.md` says about being self-documenting still applies to what remains.
