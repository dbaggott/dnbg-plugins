`/dnbg-workflow:setup` now checks whether auto-update is on for the marketplace
the plugin came from. Before, it told you to turn it on every time, even after
you had. It shows ✅ when the `/plugin` toggle or `autoUpdate` in
`~/.claude/settings.json` has it on, and ➖ with the steps to turn it on
otherwise. `DISABLE_AUTOUPDATER` without `FORCE_AUTOUPDATE_PLUGINS=1` counts as
off.
