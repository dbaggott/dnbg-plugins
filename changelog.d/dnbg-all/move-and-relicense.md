The plugins have moved to `dbaggott/dnbg-plugins`, under a new license: PolyForm
Internal Use 1.0.0 or PolyForm Strict 1.0.0, at your option. A company may use
the plugins internally, with changes, including while building products it
sells. Anyone may use them personally, unchanged. Neither license allows
distributing or selling them. See `LICENSE`.

## Migration
Installs made from the old `dbaggott/claude-plugins` stop receiving updates.
Run `/plugin marketplace remove dnbg`, then
`/plugin marketplace add dbaggott/dnbg-plugins`, then install your plugins
again, since removing a marketplace can uninstall them. If your settings name
the marketplace source in `extraKnownMarketplaces`, change its `repo` there too.
