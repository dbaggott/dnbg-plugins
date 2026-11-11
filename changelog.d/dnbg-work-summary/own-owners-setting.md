Fixed `work-summary` reading an `owners` setting that this plugin never had.
There was nowhere to set it, and the skill's searches could fail with a shell
error instead of running.

`dnbg-work-summary` now has its own `owners` setting: the GitHub orgs and logins
whose repos a recap searches. Set it from `/plugin`. It is separate from
`dnbg-workflow`'s setting of the same name, so with both plugins installed, set
each. Left empty, the skill asks which org or login to search each time.
