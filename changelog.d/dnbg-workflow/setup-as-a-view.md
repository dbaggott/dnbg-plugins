`/dnbg-workflow:setup` now ends on one list of your whole setup: each setting,
what it is now, and how to change it. Anything still needed is marked ❌ at the
top with its next step, and the optional settings sit in the same list instead
of under a separate heading. The summary directory shown is the one you set, not
the default, and a link to the configuration docs closes the list.

The session-start notice now shows while anything setup needs is missing,
which adds a missing tool, a `gh` with no login, an unsupported Claude Code and
a role configuration error to the two it covered before. It is turned off with
the new **setup_notice** option (`/plugin configure dnbg-workflow`) rather than
by a marker file. If you had silenced it by answering none or declining the
reviewer bot, it comes back once: turn it off with the option.
`~/.config/dnbg/setup-acknowledged` is no longer read and can be deleted.

After saving your accounts, setup tells you to run `/reload-plugins`, which is
enough for them to take effect in the running session.
