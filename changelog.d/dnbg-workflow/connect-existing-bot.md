Setting up on a second machine now connects it to the bots you already have
instead of offering to create them again. `/dnbg-workflow:setup` and
`reviewer-setup` look for each role's bot on GitHub first; for one that exists
you generate a private key in its settings on GitHub, and the downloaded
key is checked against the bot, saved, and removed from your Downloads folder.
Nothing is reinstalled, and each machine has a key of its own, so one machine
can be revoked by deleting its key.

Creating a bot for a role that already has one is now refused unless you give
the new one a name, so a duplicate can no longer be made by accident.

A default bot name is now kept within GitHub's 34-character limit, by
shortening a long login. Before, a login over 15 characters failed on GitHub's
form when the orchestrator bot was created.
