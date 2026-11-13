A session on a Claude Code older than the plugins support now opens with a notice
naming the version they need and the one running, and telling you to run
`claude update`. That is v2.1.207, or v2.1.299 with `dnbg-comforts` installed
for you or the current project.
Before, the notice only pointed at `/dnbg-workflow:setup`. The check reads the
version of the client actually running, not whichever `claude` is first on your
PATH. The `setup_notice` option still turns it off.

The plugin also states its minimum Claude Code version in its manifest. Claude
Code enforces that from v2.1.323, above the current floor, so it blocks nothing
until a later release raises the floor past it.
